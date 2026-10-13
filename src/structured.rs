use crate::config::Node;
use crossterm::event::{Event, KeyCode, KeyEventKind, KeyModifiers};
use ratatui::{
    layout::{Constraint, Layout, Rect},
    style::{Color, Style},
    text::Line,
    widgets::{Block, Clear, List, ListItem, ListState, Paragraph, Wrap},
    Frame,
};
use serde_json::Value;

#[derive(Clone, Debug)]
enum Slot {
    Key(String),
    Index(usize),
    Add,
    Done,
    Cancel,
}
#[derive(Clone)]
struct Page {
    title: String,
    node: Node,
    value: Value,
    selected: usize,
    slot: Option<Slot>,
    new_entry: bool,
}
#[derive(Clone)]
struct Input {
    slot: Slot,
    node: Node,
    value: String,
    cursor: usize,
    adding: bool,
    new_entry: bool,
}
#[derive(Clone)]
pub struct Structured {
    pub field: String,
    pages: Vec<Page>,
    input: Option<Input>,
    message: String,
}
pub enum Outcome {
    Saved(Value),
    Cancelled,
}

impl Structured {
    pub fn new(field: &str, title: &str, node: Node, value: Value) -> Self {
        Self {
            field: field.into(),
            pages: vec![Page {
                title: title.into(),
                node,
                value,
                selected: 0,
                slot: None,
                new_entry: false,
            }],
            input: None,
            message: "Changes stay inside this editor until Done. Esc discards this page.".into(),
        }
    }
    fn rows(&self) -> Vec<(Slot, String, Node, Value)> {
        let page = self.pages.last().unwrap();
        let mut rows = Vec::new();
        match page.node.kind.as_str() {
            "object" => {
                for (name, node) in &page.node.properties {
                    rows.push((
                        Slot::Key(name.clone()),
                        if node.label.is_empty() {
                            name.clone()
                        } else {
                            node.label.replace(" (optional)", "")
                        },
                        node.clone(),
                        page.value.get(name).cloned().unwrap_or(Value::Null),
                    ));
                }
            }
            "map" => {
                for (name, val) in page.value.as_object().into_iter().flatten() {
                    rows.push((
                        Slot::Key(name.clone()),
                        name.clone(),
                        *page.node.element.clone().unwrap(),
                        val.clone(),
                    ));
                }
            }
            "list" => {
                for (i, val) in page.value.as_array().into_iter().flatten().enumerate() {
                    let name = val
                        .get("device_name")
                        .and_then(Value::as_str)
                        .filter(|s| !s.is_empty())
                        .map(str::to_string)
                        .unwrap_or_else(|| format!("Entry {}", i + 1));
                    rows.push((
                        Slot::Index(i),
                        name,
                        *page.node.element.clone().unwrap(),
                        val.clone(),
                    ));
                }
            }
            _ => {}
        }
        if page.node.kind == "object" {
            let order: &[&str] = if page.node.properties.contains_key("access")
                && page.node.properties.contains_key("storage")
            {
                &[
                    "access",
                    "storage",
                    "network",
                    "security",
                    "placement",
                    "launch",
                ]
            } else if page.node.properties.contains_key("protocol") {
                &[
                    "protocol",
                    "from_port",
                    "to_port",
                    "cidr_ipv4",
                    "description",
                ]
            } else if page.node.properties.contains_key("device_name")
                && page.node.properties.contains_key("volume_size")
            {
                &[
                    "device_name",
                    "volume_type",
                    "volume_size",
                    "encrypted",
                    "delete_on_termination",
                    "iops",
                    "throughput",
                    "kms_key_id",
                    "snapshot_id",
                    "tags",
                ]
            } else {
                &[]
            };
            rows.sort_by_key(|(slot, _, node, _)| match slot {
                Slot::Key(key) => (
                    order
                        .iter()
                        .position(|entry| entry == key)
                        .unwrap_or(usize::MAX),
                    !node.required,
                ),
                _ => (usize::MAX, true),
            });
        }
        if matches!(page.node.kind.as_str(), "map" | "list") {
            rows.push((
                Slot::Add,
                "[ + Add entry ]".into(),
                page.node.clone(),
                Value::Null,
            ));
        }
        rows.push((
            Slot::Done,
            "[ Done · keep changes ]".into(),
            page.node.clone(),
            Value::Null,
        ));
        rows.push((
            Slot::Cancel,
            "[ Cancel · discard this page ]".into(),
            page.node.clone(),
            Value::Null,
        ));
        rows
    }
    fn put(page: &mut Page, slot: &Slot, value: Value) {
        match slot {
            Slot::Key(key) => {
                if !page.value.is_object() {
                    page.value = serde_json::json!({});
                }
                page.value
                    .as_object_mut()
                    .unwrap()
                    .insert(key.clone(), value);
            }
            Slot::Index(index) => {
                page.value.as_array_mut().unwrap()[*index] = value;
            }
            _ => {}
        }
    }
    fn edit(&mut self, slot: Slot, title: String, node: Node, value: Value) {
        match node.kind.as_str() {
            "object" | "list" | "map" => self.pages.push(Page {
                title,
                value: if value.is_null() { node.empty() } else { value },
                node,
                slot: Some(slot),
                selected: 0,
                new_entry: false,
            }),
            "bool" => {
                let next = if value.is_null() {
                    Value::Bool(true)
                } else if value == true {
                    Value::Bool(false)
                } else {
                    Value::Null
                };
                Self::put(self.pages.last_mut().unwrap(), &slot, next);
            }
            _ => {
                let text = if value.is_null() {
                    String::new()
                } else if let Some(s) = value.as_str() {
                    s.to_string()
                } else {
                    value.to_string()
                };
                self.input = Some(Input {
                    slot,
                    node,
                    cursor: text.chars().count(),
                    value: text,
                    adding: false,
                    new_entry: false,
                });
            }
        }
    }
    fn add(&mut self) {
        let page = self.pages.last_mut().unwrap();
        if page.node.kind == "map" {
            self.input = Some(Input {
                slot: Slot::Add,
                node: Node::scalar(
                    "string",
                    true,
                    "Enter a unique entry key, for example https, ssh_office, or CostCenter.",
                ),
                value: String::new(),
                cursor: 0,
                adding: true,
                new_entry: false,
            });
        } else {
            if !page.value.is_array() {
                page.value = Value::Array(vec![]);
            }
            let values = page.value.as_array_mut().unwrap();
            if page.node.max_items.is_some_and(|max| values.len() >= max) {
                self.message =
                    "This section allows only one entry. Edit the existing entry instead.".into();
                return;
            }
            let node = *page.node.element.clone().unwrap();
            let value = node.empty();
            values.push(value.clone());
            let i = values.len() - 1;
            let depth = self.pages.len();
            self.edit(Slot::Index(i), format!("Entry {}", i + 1), node, value);
            if self.pages.len() > depth {
                self.pages.last_mut().unwrap().new_entry = true;
            }
            if let Some(input) = &mut self.input {
                input.new_entry = true;
            }
        }
    }
    fn finish_input(&mut self) {
        let input = self.input.clone().unwrap();
        if input.adding {
            let key = input.value.trim();
            if key.is_empty() {
                self.message = "Entry key cannot be empty.".into();
                return;
            }
            let page = self.pages.last_mut().unwrap();
            if page.value.get(key).is_some() {
                self.message =
                    "This key already exists. Edit that entry or choose another key.".into();
                return;
            }
            let node = *page.node.element.clone().unwrap();
            let value = node.empty();
            Self::put(page, &Slot::Key(key.into()), value.clone());
            self.input = None;
            let depth = self.pages.len();
            self.edit(Slot::Key(key.into()), key.into(), node, value);
            if self.pages.len() > depth {
                self.pages.last_mut().unwrap().new_entry = true;
            }
            if let Some(input) = &mut self.input {
                input.new_entry = true;
            }
        } else {
            let value = match input.node.kind.as_str() {
                "number" if !input.value.trim().is_empty() => {
                    match serde_json::from_str::<Value>(&input.value) {
                        Ok(v) if v.is_number() => v,
                        _ => {
                            self.message =
                                "Enter a valid number, or leave blank to unset an optional value."
                                    .into();
                            return;
                        }
                    }
                }
                "number" => Value::Null,
                _ if input.value.is_empty() && !input.node.required => Value::Null,
                _ => Value::String(input.value),
            };
            if let Err(error) = input.node.validate(&value, "Value") {
                self.message = error.to_string();
                return;
            }
            Self::put(self.pages.last_mut().unwrap(), &input.slot, value);
            self.input = None;
        }
        self.message =
            "Value saved inside this editor. Done keeps the page; Esc discards it.".into();
    }
    pub fn handle(&mut self, event: Event) -> Option<Outcome> {
        if let Event::Paste(text) = event {
            if let Some(input) = &mut self.input {
                let mut chars: Vec<_> = input.value.chars().collect();
                let pasted: Vec<_> = text
                    .chars()
                    .filter(|c| !c.is_control() || *c == '\n' || *c == '\t')
                    .collect();
                let count = pasted.len();
                chars.splice(input.cursor..input.cursor, pasted);
                input.value = chars.into_iter().collect();
                input.cursor += count;
            }
            return None;
        }
        let Event::Key(key) = event else {
            return None;
        };
        if key.kind != KeyEventKind::Press {
            return None;
        }
        if key.code == KeyCode::Char('c') && key.modifiers.contains(KeyModifiers::CONTROL) {
            return Some(Outcome::Cancelled);
        }
        if let Some(input) = &mut self.input {
            match key.code {
                KeyCode::Esc => {
                    if input.new_entry {
                        Self::remove(self.pages.last_mut().unwrap(), &input.slot);
                    }
                    self.input = None;
                }
                KeyCode::Enter | KeyCode::Char('s')
                    if key.code == KeyCode::Enter
                        || key.modifiers.contains(KeyModifiers::CONTROL) =>
                {
                    self.finish_input()
                }
                KeyCode::Char('u') if key.modifiers.contains(KeyModifiers::CONTROL) => {
                    input.value.clear();
                    input.cursor = 0;
                }
                KeyCode::Left => input.cursor = input.cursor.saturating_sub(1),
                KeyCode::Right => {
                    input.cursor = (input.cursor + 1).min(input.value.chars().count())
                }
                KeyCode::Home => input.cursor = 0,
                KeyCode::End => input.cursor = input.value.chars().count(),
                KeyCode::Backspace if input.cursor > 0 => {
                    let mut chars: Vec<_> = input.value.chars().collect();
                    chars.remove(input.cursor - 1);
                    input.value = chars.into_iter().collect();
                    input.cursor -= 1;
                }
                KeyCode::Delete if input.cursor < input.value.chars().count() => {
                    let mut chars: Vec<_> = input.value.chars().collect();
                    chars.remove(input.cursor);
                    input.value = chars.into_iter().collect();
                }
                KeyCode::Char(c)
                    if !key
                        .modifiers
                        .intersects(KeyModifiers::CONTROL | KeyModifiers::ALT) =>
                {
                    let mut chars: Vec<_> = input.value.chars().collect();
                    chars.insert(input.cursor, c);
                    input.value = chars.into_iter().collect();
                    input.cursor += 1;
                }
                _ => {}
            }
            return None;
        }
        let rows = self.rows();
        let page = self.pages.last_mut().unwrap();
        match key.code {
            KeyCode::Down | KeyCode::Tab => page.selected = (page.selected + 1).min(rows.len() - 1),
            KeyCode::Up | KeyCode::BackTab => page.selected = page.selected.saturating_sub(1),
            KeyCode::Char('a') if matches!(page.node.kind.as_str(), "map" | "list") => self.add(),
            KeyCode::Delete | KeyCode::Char('d') => {
                match &rows[page.selected].0 {
                    Slot::Key(key) if page.node.kind == "map" => {
                        page.value.as_object_mut().unwrap().remove(key);
                    }
                    Slot::Key(key) if !rows[page.selected].2.required => {
                        page.value.as_object_mut().map(|map| map.remove(key));
                    }
                    Slot::Index(index) => {
                        page.value.as_array_mut().unwrap().remove(*index);
                    }
                    _ => {
                        self.message =
                            "Required fields cannot be removed; optional values can be unset."
                                .into();
                    }
                }
                let selected = page.selected;
                let count = self.rows().len();
                self.pages.last_mut().unwrap().selected = selected.min(count - 1);
            }
            KeyCode::Esc => {
                if self.pages.len() == 1 {
                    return Some(Outcome::Cancelled);
                }
                self.cancel_page();
                self.message = "Child page discarded. Parent values are unchanged.".into();
            }
            KeyCode::Enter => {
                let (slot, title, node, value) = rows[page.selected].clone();
                match slot {
                    Slot::Add => self.add(),
                    Slot::Done => return self.done(),
                    Slot::Cancel => {
                        if self.pages.len() == 1 {
                            return Some(Outcome::Cancelled);
                        }
                        self.cancel_page();
                    }
                    _ => self.edit(slot, title, node, value),
                }
            }
            KeyCode::Char('s') if key.modifiers.contains(KeyModifiers::CONTROL) => {
                return self.done()
            }
            _ => {}
        }
        None
    }
    fn remove(page: &mut Page, slot: &Slot) {
        match slot {
            Slot::Key(key) => {
                page.value.as_object_mut().map(|values| values.remove(key));
            }
            Slot::Index(i) => {
                page.value.as_array_mut().unwrap().remove(*i);
            }
            _ => {}
        }
    }
    fn cancel_page(&mut self) {
        let page = self.pages.pop().unwrap();
        if page.new_entry {
            Self::remove(self.pages.last_mut().unwrap(), &page.slot.unwrap());
        }
    }
    fn done(&mut self) -> Option<Outcome> {
        let page = self.pages.last().unwrap();
        if let Err(error) = page.node.validate(&page.value, &page.title) {
            self.message = error.to_string();
            return None;
        }
        let page = self.pages.pop().unwrap();
        if let Some(parent) = self.pages.last_mut() {
            Self::put(parent, &page.slot.unwrap(), page.value);
            self.message = "Section kept. Done on the parent page keeps it in the form.".into();
            None
        } else {
            Some(Outcome::Saved(page.value))
        }
    }
    pub fn draw(&self, frame: &mut Frame, color: bool) {
        let bounds = frame.area();
        let multiline = self.input.as_ref().is_some_and(|input| {
            input.value.contains('\n')
                || matches!(&input.slot, Slot::Key(key) if key == "user_data")
        });
        let (wanted_width, wanted_height) = if self.input.is_some() {
            if multiline {
                (100, 24)
            } else {
                (68, 12)
            }
        } else {
            (88, (self.rows().len() as u16).saturating_add(10))
        };
        let width = wanted_width.min(bounds.width.saturating_sub(2));
        let height = wanted_height.min(bounds.height.saturating_sub(2));
        let area = Rect::new(
            bounds.x + (bounds.width - width) / 2,
            bounds.y + (bounds.height - height) / 2,
            width,
            height,
        );
        frame.render_widget(Clear, area);
        let page = self.pages.last().unwrap();
        let cyan = if color { Color::Cyan } else { Color::Reset };
        let title = if let Some(input) = &self.input {
            if input.adding {
                format!(" {} · Add entry ", page.title)
            } else {
                format!(
                    " Edit {} ",
                    match &input.slot {
                        Slot::Key(key) => key.as_str(),
                        _ => "value",
                    }
                )
            }
        } else {
            format!(" {} ", page.title)
        };
        let block = Block::bordered()
            .title(title)
            .border_style(Style::default().fg(cyan));
        let inner = block.inner(area);
        frame.render_widget(block, area);
        let [intro, body, message, footer] = Layout::vertical([
            Constraint::Length(2),
            Constraint::Min(1),
            Constraint::Length(2),
            Constraint::Length(2),
        ])
        .areas(inner);
        let rows = self.rows();
        let help = if let Some(input) = &self.input {
            input.node.help.as_str()
        } else {
            rows[page.selected].2.help.as_str()
        };
        frame.render_widget(Paragraph::new(help).wrap(Wrap { trim: false }), intro);
        if let Some(input) = &self.input {
            let block = Block::bordered().title(" Value ");
            let inner = block.inner(body);
            let width = inner.width.max(1) as usize;
            let mut lines = vec![String::new()];
            let mut x = 0usize;
            let mut cursor = (0usize, 0usize);
            for (index, c) in input.value.chars().chain(std::iter::once('\0')).enumerate() {
                if index == input.cursor {
                    cursor = (x, lines.len() - 1);
                }
                if c == '\0' {
                    break;
                }
                if c == '\n' {
                    lines.push(String::new());
                    x = 0;
                    continue;
                }
                let size = unicode_width::UnicodeWidthChar::width(c)
                    .unwrap_or(0)
                    .max(1);
                if x + size > width {
                    lines.push(String::new());
                    x = 0;
                    if index == input.cursor {
                        cursor = (x, lines.len() - 1);
                    }
                }
                lines.last_mut().unwrap().push(c);
                x += size;
                if x >= width {
                    lines.push(String::new());
                    x = 0;
                }
            }
            let scroll = cursor
                .1
                .saturating_sub(inner.height.saturating_sub(1) as usize);
            frame.render_widget(
                Paragraph::new(lines.into_iter().map(Line::from).collect::<Vec<_>>())
                    .scroll((scroll.min(u16::MAX as usize) as u16, 0))
                    .block(block),
                body,
            );
            if inner.width > 0 && inner.height > 0 {
                frame.set_cursor_position((
                    inner.x + cursor.0.min(width - 1) as u16,
                    inner.y + (cursor.1 - scroll).min(inner.height as usize - 1) as u16,
                ));
            }
        } else {
            let items = rows
                .iter()
                .map(|(slot, name, node, value)| {
                    let text = if matches!(slot, Slot::Add | Slot::Done | Slot::Cancel) {
                        name.clone()
                    } else {
                        format!(
                            "{} {}  =  {}",
                            name,
                            if page.node.kind != "object" {
                                "[entry]"
                            } else if node.required {
                                "[required]"
                            } else {
                                "[optional]"
                            },
                            if node.label.is_empty() {
                                summary(value)
                            } else {
                                summary(value).split(" · ").next().unwrap_or("").to_string()
                            }
                        )
                    };
                    ListItem::new(Line::from(text))
                })
                .collect::<Vec<_>>();
            let mut state = ListState::default().with_selected(Some(page.selected));
            frame.render_stateful_widget(
                List::new(items)
                    .highlight_symbol(" > ")
                    .highlight_style(Style::default().fg(cyan)),
                body,
                &mut state,
            );
        }
        frame.render_widget(
            Paragraph::new(self.message.as_str()).wrap(Wrap { trim: false }),
            message,
        );
        frame.render_widget(Paragraph::new(if self.input.is_some() { "Enter Keep value · Ctrl+U Clear · Esc Cancel" } else { "↑↓ / Tab Navigate · Enter Edit · a Add entry · d Unset/Delete · Ctrl+S Done · Esc Discard page" }).wrap(Wrap { trim: false }), footer);
    }
}

pub fn summary(value: &Value) -> String {
    match value {
        Value::Null => "unset · provider default".into(),
        Value::Object(values)
            if values.contains_key("protocol") && values.contains_key("cidr_ipv4") =>
        {
            format!(
                "{} {}–{} · {}",
                values["protocol"].as_str().unwrap_or(""),
                values.get("from_port").unwrap_or(&Value::Null),
                values.get("to_port").unwrap_or(&Value::Null),
                values["cidr_ipv4"].as_str().unwrap_or("")
            )
        }
        Value::Object(values)
            if values.contains_key("device_name") && values.contains_key("volume_size") =>
        {
            format!(
                "{} · {} GiB · encrypted {}",
                values
                    .get("volume_type")
                    .and_then(Value::as_str)
                    .unwrap_or("default type"),
                values["volume_size"],
                values.get("encrypted").unwrap_or(&Value::Null)
            )
        }
        Value::Object(values) => format!(
            "{} setting(s) · Enter to edit",
            values.iter().filter(|(_, v)| is_set(v)).count()
        ),
        Value::Array(values) => format!("{} entry/entries · Enter to edit", values.len()),
        Value::String(value) => value.replace('\n', " ↵ ").chars().take(90).collect(),
        _ => value.to_string(),
    }
}

pub fn is_set(value: &Value) -> bool {
    match value {
        Value::Null => false,
        Value::Object(values) => values.values().any(is_set),
        Value::Array(values) => !values.is_empty(),
        _ => true,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crossterm::event::KeyEvent;
    fn key(code: KeyCode) -> Event {
        Event::Key(KeyEvent::new(code, KeyModifiers::NONE))
    }
    fn done() -> Event {
        Event::Key(KeyEvent::new(KeyCode::Char('s'), KeyModifiers::CONTROL))
    }
    fn type_text(editor: &mut Structured, text: &str) {
        for c in text.chars() {
            editor.handle(key(KeyCode::Char(c)));
        }
    }
    fn select(editor: &mut Structured, name: &str) {
        let index = editor
            .rows()
            .iter()
            .position(|(slot, _, _, _)| matches!(slot, Slot::Key(key) if key == name))
            .unwrap();
        editor.pages.last_mut().unwrap().selected = index;
    }
    #[test]
    fn creates_multiple_named_rules_without_leaving_the_parent_editor() {
        let mut editor = Structured::new(
            "ingress",
            "Ingress",
            crate::config::rules_schema(),
            serde_json::json!({}),
        );
        editor.handle(key(KeyCode::Char('a')));
        type_text(&mut editor, "https");
        editor.handle(key(KeyCode::Enter));
        assert!(editor.handle(done()).is_none());
        editor.handle(key(KeyCode::Char('a')));
        type_text(&mut editor, "ssh_office");
        editor.handle(key(KeyCode::Enter));
        for field in ["from_port", "to_port"] {
            select(&mut editor, field);
            editor.handle(key(KeyCode::Enter));
            editor.handle(Event::Key(KeyEvent::new(
                KeyCode::Char('u'),
                KeyModifiers::CONTROL,
            )));
            type_text(&mut editor, "22");
            editor.handle(key(KeyCode::Enter));
        }
        editor.handle(done());
        let Some(Outcome::Saved(value)) = editor.handle(done()) else {
            panic!("rule list was not saved");
        };
        assert_eq!(value["https"]["from_port"], 443);
        assert_eq!(value["ssh_office"]["from_port"], 22);
    }
    #[test]
    fn cancelling_a_new_disk_does_not_leave_an_invalid_placeholder() {
        let node = crate::config::ec2_schema().properties["ebs_block_device"].clone();
        let mut editor = Structured::new("disks", "EBS", node, serde_json::json!([]));
        editor.handle(key(KeyCode::Char('a')));
        editor.handle(key(KeyCode::Esc));
        let Some(Outcome::Saved(value)) = editor.handle(done()) else {
            panic!("disk editor not saved");
        };
        assert_eq!(value, serde_json::json!([]));
    }
    #[test]
    fn required_disk_fields_and_invalid_rule_ports_keep_the_editor_open() {
        let node = crate::config::ec2_schema().properties["ebs_block_device"].clone();
        let mut editor = Structured::new("disks", "EBS", node, serde_json::json!([]));
        editor.handle(key(KeyCode::Char('a')));
        assert!(editor.handle(done()).is_none());
        assert!(editor.message.contains("device_name"));
        let node = crate::config::rules_schema();
        assert!(node.validate(&serde_json::json!({"bad":{"protocol":"tcp","from_port":90,"to_port":20,"cidr_ipv4":"10.0.0.0/16","description":""}}), "ingress").is_err());
    }
}
