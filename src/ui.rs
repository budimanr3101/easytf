use crate::model::{self, Backend, Environment, Instance, Project, Rule, SecurityGroup};
use crate::project::{self, Change, Loaded};
use anyhow::{bail, Result};
use crossterm::event::{self, Event, KeyCode, KeyEvent, KeyEventKind, KeyModifiers};
use ratatui::{
    layout::{Constraint, Layout, Rect},
    style::{Color, Modifier, Style},
    text::{Line, Span},
    widgets::{Block, Borders, Clear, List, ListItem, ListState, Paragraph, Wrap},
    Frame,
};
use std::collections::BTreeMap;
use std::path::PathBuf;
use unicode_width::UnicodeWidthStr;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Stage {
    Welcome,
    Project,
    Environments,
    Backend,
    Resources,
    Review,
    Done,
}

impl Stage {
    fn label(self) -> &'static str {
        match self {
            Self::Welcome => "Welcome",
            Self::Project => "Project",
            Self::Environments => "Environments",
            Self::Backend => "Backend",
            Self::Resources => "Resources",
            Self::Review => "Review",
            Self::Done => "Generated",
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
enum ResourceRow {
    Instance(String),
    SecurityGroup(String),
}

#[derive(Debug, Clone)]
enum FieldKind {
    Text,
    Choice(Vec<String>),
    Toggle,
}

#[derive(Debug, Clone)]
struct Field {
    name: &'static str,
    label: &'static str,
    help: &'static str,
    value: String,
    kind: FieldKind,
    locked: bool,
}

impl Field {
    fn text(
        name: &'static str,
        label: &'static str,
        help: &'static str,
        value: impl Into<String>,
    ) -> Self {
        Self {
            name,
            label,
            help,
            value: value.into(),
            kind: FieldKind::Text,
            locked: false,
        }
    }
    fn choice(
        name: &'static str,
        label: &'static str,
        help: &'static str,
        values: &[&str],
        value: &str,
    ) -> Self {
        Self {
            name,
            label,
            help,
            value: value.into(),
            kind: FieldKind::Choice(values.iter().map(|s| (*s).into()).collect()),
            locked: false,
        }
    }
    fn toggle(name: &'static str, label: &'static str, help: &'static str, value: bool) -> Self {
        Self {
            name,
            label,
            help,
            value: value.to_string(),
            kind: FieldKind::Toggle,
            locked: false,
        }
    }
}

#[derive(Debug, Clone)]
enum EditKind {
    Project,
    Open,
    Resume,
    AddEnvironment,
    Environment(String),
    Backend,
    Instance(Option<String>),
    SecurityGroup(Option<String>),
}

#[derive(Debug, Clone)]
struct Editor {
    title: String,
    kind: EditKind,
    fields: Vec<Field>,
    selected: usize,
    cursor: usize,
}

impl Editor {
    fn new(title: &str, kind: EditKind, fields: Vec<Field>) -> Self {
        let cursor = fields.first().map(|f| f.value.chars().count()).unwrap_or(0);
        Self {
            title: title.into(),
            kind,
            fields,
            selected: 0,
            cursor,
        }
    }
    fn get(&self, name: &str) -> &str {
        self.fields
            .iter()
            .find(|f| f.name == name)
            .map(|f| f.value.as_str())
            .unwrap_or("")
    }
    fn visible(&self) -> Vec<usize> {
        self.fields
            .iter()
            .enumerate()
            .filter(|(_, f)| match f.name {
                "bucket" | "backend_region" | "key_pattern" => self.get("backend") == "S3",
                "existing_sg_ids" => {
                    matches!(self.get("sg_source"), "Use existing" | "Existing + linked")
                }
                "sg_keys" => matches!(self.get("sg_source"), "Link project" | "Existing + linked"),
                "new_sg_key" | "new_sg_name" | "new_sg_ingress" => {
                    self.get("sg_source") == "Create new"
                }
                "new_sg_port" | "new_sg_cidr" => {
                    self.get("sg_source") == "Create new" && self.get("new_sg_ingress") == "true"
                }
                "protocol" | "cidr" => self.get("ingress_enabled") == "true",
                "from_port" | "to_port" => {
                    self.get("ingress_enabled") == "true" && self.get("protocol") != "-1"
                }
                _ => true,
            })
            .map(|(i, _)| i)
            .collect()
    }
    fn select(&mut self, direction: isize) {
        let visible = self.visible();
        let position = visible
            .iter()
            .position(|i| *i == self.selected)
            .unwrap_or(0);
        let next = (position as isize + direction).rem_euclid(visible.len() as isize) as usize;
        self.selected = visible[next];
        self.cursor = self.fields[self.selected].value.chars().count();
    }
    fn cycle(&mut self, direction: isize) {
        let field = &mut self.fields[self.selected];
        if field.locked {
            return;
        }
        match &field.kind {
            FieldKind::Choice(values) => {
                let pos = values.iter().position(|v| *v == field.value).unwrap_or(0);
                field.value = values
                    [(pos as isize + direction).rem_euclid(values.len() as isize) as usize]
                    .clone();
            }
            FieldKind::Toggle => field.value = (field.value != "true").to_string(),
            FieldKind::Text => {}
        }
        self.cursor = field.value.chars().count();
    }
    fn input(&mut self, key: KeyEvent) {
        match key.code {
            KeyCode::Tab | KeyCode::Down => self.select(1),
            KeyCode::BackTab | KeyCode::Up => self.select(-1),
            KeyCode::Enter => {
                if matches!(self.fields[self.selected].kind, FieldKind::Text) {
                    self.select(1);
                } else {
                    self.cycle(1);
                }
            }
            KeyCode::Left => {
                if matches!(self.fields[self.selected].kind, FieldKind::Text) {
                    self.cursor = self.cursor.saturating_sub(1);
                } else {
                    self.cycle(-1);
                }
            }
            KeyCode::Right => {
                if matches!(self.fields[self.selected].kind, FieldKind::Text) {
                    self.cursor =
                        (self.cursor + 1).min(self.fields[self.selected].value.chars().count());
                } else {
                    self.cycle(1);
                }
            }
            KeyCode::Home => self.cursor = 0,
            KeyCode::End => self.cursor = self.fields[self.selected].value.chars().count(),
            KeyCode::Backspace if !self.fields[self.selected].locked => {
                let field = &mut self.fields[self.selected];
                if matches!(field.kind, FieldKind::Text) && self.cursor > 0 {
                    let mut chars: Vec<char> = field.value.chars().collect();
                    chars.remove(self.cursor - 1);
                    field.value = chars.into_iter().collect();
                    self.cursor -= 1;
                }
            }
            KeyCode::Delete if !self.fields[self.selected].locked => {
                let field = &mut self.fields[self.selected];
                let mut chars: Vec<char> = field.value.chars().collect();
                if matches!(field.kind, FieldKind::Text) && self.cursor < chars.len() {
                    chars.remove(self.cursor);
                    field.value = chars.into_iter().collect();
                }
            }
            KeyCode::Char('u') if key.modifiers.contains(KeyModifiers::CONTROL) => {
                let field = &mut self.fields[self.selected];
                if !field.locked && matches!(field.kind, FieldKind::Text) {
                    field.value.clear();
                    self.cursor = 0;
                }
            }
            KeyCode::Char(c)
                if !key
                    .modifiers
                    .intersects(KeyModifiers::CONTROL | KeyModifiers::ALT) =>
            {
                if !self.fields[self.selected].locked {
                    if matches!(self.fields[self.selected].kind, FieldKind::Text) {
                        self.paste(&c.to_string());
                    } else if c == ' ' {
                        self.cycle(1);
                    }
                }
            }
            _ => {}
        }
    }
    fn paste(&mut self, value: &str) {
        let field = &mut self.fields[self.selected];
        if field.locked || !matches!(field.kind, FieldKind::Text) {
            return;
        }
        let mut chars: Vec<char> = field.value.chars().collect();
        let added: Vec<char> = value
            .chars()
            .filter(|c| !c.is_control())
            .take(4096usize.saturating_sub(chars.len()))
            .collect();
        let count = added.len();
        chars.splice(self.cursor..self.cursor, added);
        field.value = chars.into_iter().collect();
        self.cursor += count;
    }
}

#[derive(Debug, Clone)]
enum Modal {
    Help,
    Generate,
    Remove(ResourceRow),
    Quit,
}

#[derive(Clone)]
pub struct App {
    pub project: Project,
    pub output: PathBuf,
    pub loaded: Option<Loaded>,
    pub stage: Stage,
    editor: Option<Editor>,
    modal: Option<Modal>,
    selected: usize,
    env_index: usize,
    preview: usize,
    preview_scroll: u16,
    environment_options: Vec<String>,
    inactive: BTreeMap<String, Environment>,
    pub message: String,
    pub error: bool,
    pub quit: bool,
    dirty: bool,
    color: bool,
    draft_path: PathBuf,
    review_files: Vec<Change>,
    screen_width: std::cell::Cell<u16>,
    compact_preview: bool,
    compact_review_diff: bool,
}

impl App {
    pub fn new(
        project: Project,
        output: PathBuf,
        loaded: Option<Loaded>,
        demo: bool,
        color: bool,
    ) -> Self {
        let mut options = vec!["dev".into(), "staging".into(), "prod".into()];
        for name in project.environments.keys() {
            if !options.contains(name) {
                options.push(name.clone());
            }
        }
        let home = std::env::var_os("HOME")
            .map(PathBuf::from)
            .unwrap_or_else(|| PathBuf::from("."));
        let stage = if demo || loaded.is_some() {
            Stage::Resources
        } else {
            Stage::Welcome
        };
        Self {
            project,
            output,
            loaded,
            stage,
            editor: None,
            modal: None,
            selected: 0,
            env_index: 0,
            preview: 0,
            preview_scroll: 0,
            environment_options: options,
            inactive: BTreeMap::new(),
            message: if demo {
                "Demo workspace — replace placeholder AWS IDs before planning.".into()
            } else {
                "Files only · AWS discovery and Terraform apply are outside this MVP.".into()
            },
            error: false,
            quit: false,
            dirty: demo,
            color,
            draft_path: home.join(".local/state/easytf/draft.json"),
            review_files: vec![],
            screen_width: std::cell::Cell::new(140),
            compact_preview: false,
            compact_review_diff: false,
        }
    }

    fn color(&self, color: Color) -> Color {
        if self.color {
            color
        } else {
            Color::Reset
        }
    }
    fn environment_names(&self) -> Vec<String> {
        let mut names: Vec<_> = self.project.environments.keys().cloned().collect();
        let rank = |name: &str| match name {
            "dev" => 0,
            "staging" => 1,
            "prod" => 2,
            _ => 3,
        };
        names.sort_by(|a, b| (rank(a), a).cmp(&(rank(b), b)));
        names
    }
    fn env_name(&self) -> String {
        self.environment_names()
            .get(self.env_index)
            .cloned()
            .unwrap_or_else(|| "dev".into())
    }
    fn rows(&self) -> Vec<ResourceRow> {
        self.project
            .environments
            .get(&self.env_name())
            .map(|env| {
                env.values
                    .instances
                    .keys()
                    .map(|k| ResourceRow::Instance(k.clone()))
                    .chain(
                        env.values
                            .security_groups
                            .keys()
                            .map(|k| ResourceRow::SecurityGroup(k.clone())),
                    )
                    .collect()
            })
            .unwrap_or_default()
    }
    fn status(&mut self, message: impl Into<String>, error: bool) {
        self.message = message.into();
        self.error = error;
    }
    fn go(&mut self, stage: Stage) {
        self.stage = stage;
        self.selected = 0;
        self.preview_scroll = 0;
        self.editor = None;
        self.compact_preview = false;
        self.compact_review_diff = false;
        if stage == Stage::Project {
            self.edit_project();
        }
        if stage == Stage::Backend {
            self.edit_backend();
        }
        match stage {
            Stage::Project => self.status("Step 1/5: name your project and choose its folder. Enter advances; Ctrl+N finishes the form.", false),
            Stage::Environments => self.status("Step 2/5: Space selects environments. Enter edits region/profile. Ctrl+N continues to backend.", false),
            Stage::Backend => self.status("Step 3/5: choose state storage. Enter advances; Ctrl+N finishes and opens resources.", false),
            Stage::Resources => self.status("Step 4/5: a adds EC2, s adds SG. Tab changes environment. Press r when ready to review files.", false),
            _ => {}
        }
        if stage == Stage::Review {
            match project::changes(&self.output, &self.project) {
                Ok(files) => {
                    self.review_files = files;
                    self.status(
                        "Review file changes. Press g to generate; no Terraform apply is executed.",
                        false,
                    );
                }
                Err(e) => {
                    self.review_files.clear();
                    self.status(e.to_string(), true);
                }
            }
        }
    }

    pub fn handle(&mut self, event: Event) {
        if let Event::Paste(value) = &event {
            if let Some(editor) = &mut self.editor {
                editor.paste(value);
            }
            return;
        }
        let Event::Key(key) = event else {
            return;
        };
        if key.kind != KeyEventKind::Press {
            return;
        }
        if self.modal.is_some() {
            self.handle_modal(key);
            return;
        }
        if key.modifiers.contains(KeyModifiers::CONTROL) && key.code == KeyCode::Char('c') {
            self.modal = Some(Modal::Quit);
            return;
        }
        if self.editor.is_some() {
            match key.code {
                KeyCode::Esc => {
                    self.editor = None;
                    if self.stage == Stage::Project {
                        self.go(Stage::Welcome);
                    } else if self.stage == Stage::Backend {
                        self.go(Stage::Environments);
                    }
                    self.status("Unsaved form changes discarded.", false);
                }
                KeyCode::F(1) => self.modal = Some(Modal::Help),
                KeyCode::Enter
                    if key.modifiers.contains(KeyModifiers::CONTROL)
                        || self
                            .editor
                            .as_ref()
                            .is_some_and(|e| e.visible().last() == Some(&e.selected)) =>
                {
                    self.commit_editor(true)
                }
                KeyCode::Char('n') if key.modifiers.contains(KeyModifiers::CONTROL) => {
                    self.commit_editor(true)
                }
                KeyCode::F(2) => self.commit_editor(true),
                KeyCode::Char('s') if key.modifiers.contains(KeyModifiers::CONTROL) => {
                    self.commit_editor(false)
                }
                _ => self.editor.as_mut().unwrap().input(key),
            }
            return;
        }
        if key.code == KeyCode::Char('?') || key.code == KeyCode::F(1) {
            self.modal = Some(Modal::Help);
            return;
        }
        if key.code == KeyCode::Char('q') {
            self.modal = Some(Modal::Quit);
            return;
        }
        if key.code == KeyCode::Char('s') && key.modifiers.contains(KeyModifiers::CONTROL) {
            self.save_draft();
            return;
        }
        if key.code == KeyCode::F(3) || key.code == KeyCode::Char('p') {
            if self.screen_width.get() < 110 {
                if !self.compact_preview {
                    self.compact_preview = true;
                    self.preview = 0;
                } else if self.preview == 2 {
                    self.compact_preview = false;
                    self.preview = 0;
                } else {
                    self.preview += 1;
                }
            } else {
                self.preview = (self.preview + 1) % 3;
            }
            self.preview_scroll = 0;
            return;
        }
        if self.compact_preview && matches!(key.code, KeyCode::Up | KeyCode::Down) {
            self.preview_scroll = if key.code == KeyCode::Down {
                self.preview_scroll.saturating_add(1)
            } else {
                self.preview_scroll.saturating_sub(1)
            };
            return;
        }
        if key.code == KeyCode::PageDown {
            self.preview_scroll = self.preview_scroll.saturating_add(8);
            return;
        }
        if key.code == KeyCode::PageUp {
            self.preview_scroll = self.preview_scroll.saturating_sub(8);
            return;
        }
        let key = if key.code == KeyCode::Char('n') && key.modifiers.contains(KeyModifiers::CONTROL)
        {
            KeyEvent::new(KeyCode::F(2), KeyModifiers::NONE)
        } else {
            key
        };
        match self.stage {
            Stage::Welcome => match key.code {
                KeyCode::Up | KeyCode::Char('k') => self.selected = (self.selected + 3) % 4,
                KeyCode::Down | KeyCode::Char('j') => self.selected = (self.selected + 1) % 4,
                KeyCode::Enter => match self.selected {
                    0 => {
                        self.project = Project::empty("my-project");
                        self.loaded = None;
                        self.go(Stage::Project);
                    }
                    1 => {
                        self.editor = Some(Editor::new(
                            "Open EasyTF project",
                            EditKind::Open,
                            vec![Field::text(
                                "path",
                                "Project folder",
                                "Choose a folder containing .easytf.toml",
                                self.output.to_string_lossy(),
                            )],
                        ))
                    }
                    2 => {
                        self.editor = Some(Editor::new(
                            "Resume saved draft",
                            EditKind::Resume,
                            vec![Field::text(
                                "path",
                                "Draft file",
                                "Drafts stay local and do not create Terraform files",
                                self.draft_path.to_string_lossy(),
                            )],
                        ))
                    }
                    _ => {
                        self.project = Project::demo();
                        self.loaded = None;
                        self.dirty = true;
                        self.go(Stage::Resources);
                        self.status("Demo IDs are placeholders. Replace them before running Terraform plan.", false);
                    }
                },
                _ => {}
            },
            Stage::Project => {
                if key.code == KeyCode::Enter {
                    self.edit_project();
                }
            }
            Stage::Environments => match key.code {
                KeyCode::Up | KeyCode::Char('k') => self.selected = self.selected.saturating_sub(1),
                KeyCode::Down | KeyCode::Char('j') => {
                    self.selected = (self.selected + 1).min(self.environment_options.len() - 1)
                }
                KeyCode::Char(' ') => self.toggle_environment(),
                KeyCode::Enter => {
                    let name = self.environment_options[self.selected].clone();
                    if self.project.environments.contains_key(&name) {
                        self.edit_environment(&name);
                    } else {
                        self.status(
                            "Select this environment with Space before editing it.",
                            true,
                        );
                    }
                }
                KeyCode::Char('a') => {
                    self.editor = Some(Editor::new(
                        "Add environment",
                        EditKind::AddEnvironment,
                        vec![Field::text(
                            "name",
                            "Environment name",
                            "Examples: qa, preview, sandbox",
                            "",
                        )],
                    ))
                }
                KeyCode::F(2) => {
                    if self.project.environments.is_empty() {
                        self.status("Select at least one environment.", true);
                    } else {
                        self.go(Stage::Backend);
                    }
                }
                KeyCode::Esc => self.go(Stage::Project),
                _ => {}
            },
            Stage::Backend => match key.code {
                KeyCode::F(2) => self.go(Stage::Resources),
                KeyCode::Enter => self.edit_backend(),
                KeyCode::Esc => self.go(Stage::Environments),
                _ => {}
            },
            Stage::Resources => match key.code {
                KeyCode::Up | KeyCode::Char('k') => self.selected = self.selected.saturating_sub(1),
                KeyCode::Down | KeyCode::Char('j') => {
                    self.selected = (self.selected + 1).min(self.rows().len().saturating_sub(1))
                }
                KeyCode::Char('a') => self.edit_instance(None),
                KeyCode::Char('s') => self.edit_security_group(None),
                KeyCode::Enter => match self.rows().get(self.selected).cloned() {
                    Some(ResourceRow::Instance(key)) => self.edit_instance(Some(key)),
                    Some(ResourceRow::SecurityGroup(key)) => self.edit_security_group(Some(key)),
                    None => self.edit_instance(None),
                },
                KeyCode::Delete | KeyCode::Char('d') => {
                    if let Some(row) = self.rows().get(self.selected).cloned() {
                        self.modal = Some(Modal::Remove(row));
                    }
                }
                KeyCode::Char(']') | KeyCode::Tab => self.switch_environment(1),
                KeyCode::Char('[') | KeyCode::BackTab => self.switch_environment(-1),
                KeyCode::Char('e') => self.edit_environment(&self.env_name()),
                KeyCode::Char('n') => self.go(Stage::Environments),
                KeyCode::F(2) | KeyCode::Char('r') => self.go(Stage::Review),
                KeyCode::Esc => {
                    if self.compact_preview {
                        self.compact_preview = false;
                    } else {
                        self.go(Stage::Backend);
                    }
                }
                _ => {}
            },
            Stage::Review => match key.code {
                KeyCode::Enter => {
                    if self.screen_width.get() < 110 {
                        self.compact_review_diff = !self.compact_review_diff;
                    } else {
                        self.status("Selected file diff is shown on the right. PgUp/PgDn scrolls it; g generates files.", false);
                    }
                }
                KeyCode::Up | KeyCode::Char('k') => {
                    self.selected = self.selected.saturating_sub(1);
                    self.preview_scroll = 0;
                }
                KeyCode::Down | KeyCode::Char('j') => {
                    self.selected =
                        (self.selected + 1).min(self.review_files.len().saturating_sub(1));
                    self.preview_scroll = 0;
                }
                KeyCode::Char('g') | KeyCode::F(2) => {
                    if self.project.validate().is_ok() && !self.review_files.is_empty() {
                        self.modal = Some(Modal::Generate);
                    } else {
                        self.status("Resolve validation errors before generating files.", true);
                    }
                }
                KeyCode::Esc => {
                    if self.compact_review_diff {
                        self.compact_review_diff = false;
                    } else {
                        self.go(Stage::Resources);
                    }
                }
                _ => {}
            },
            Stage::Done => match key.code {
                KeyCode::Enter | KeyCode::Esc => self.go(Stage::Resources),
                _ => {}
            },
        }
    }

    fn switch_environment(&mut self, direction: isize) {
        let count = self.project.environments.len();
        if count > 0 {
            self.env_index =
                (self.env_index as isize + direction).rem_euclid(count as isize) as usize;
        }
        self.selected = 0;
        self.preview_scroll = 0;
    }

    fn toggle_environment(&mut self) {
        let name = self.environment_options[self.selected].clone();
        if self.project.environments.contains_key(&name) {
            if self
                .loaded
                .as_ref()
                .is_some_and(|l| l.project.environments.contains_key(&name))
            {
                self.status("Removing existing environments is outside this MVP. Their state/infrastructure needs an explicit workflow.", true);
                return;
            }
            self.inactive.insert(
                name.clone(),
                self.project.environments.remove(&name).unwrap(),
            );
        } else {
            let mut env = self.inactive.remove(&name).unwrap_or_default();
            env.values
                .tags
                .entry("Project".into())
                .or_insert_with(|| self.project.name.clone());
            env.values
                .tags
                .entry("Environment".into())
                .or_insert_with(|| name.clone());
            self.project.environments.insert(name, env);
        }
        self.env_index = self
            .env_index
            .min(self.project.environments.len().saturating_sub(1));
        self.dirty = true;
    }

    fn edit_project(&mut self) {
        let mut name = Field::text(
            "name",
            "Project name",
            "Stable project identifier; letters, numbers, '_' and '-'",
            self.project.name.clone(),
        );
        let mut path = Field::text(
            "path",
            "Output folder",
            "New empty folder, or an existing EasyTF project opened from Welcome",
            self.output.to_string_lossy(),
        );
        name.locked = self.loaded.is_some();
        path.locked = self.loaded.is_some();
        self.editor = Some(Editor::new(
            "Project setup",
            EditKind::Project,
            vec![name, path],
        ));
    }

    fn edit_environment(&mut self, name: &str) {
        let values = &self.project.environments[name].values;
        self.editor = Some(Editor::new(
            &format!("Environment · {name}"),
            EditKind::Environment(name.into()),
            vec![
                Field::text(
                    "region",
                    "Deployment AWS region",
                    "Resource region; backend region is configured separately",
                    values.aws_region.clone(),
                ),
                Field::text(
                    "profile",
                    "AWS profile (optional)",
                    "Blank uses the standard AWS credential chain; no credentials are stored",
                    values.aws_profile.clone().unwrap_or_default(),
                ),
                Field::text(
                    "tags",
                    "Default tags (JSON)",
                    "Example: {\"Project\":\"payment\",\"Environment\":\"dev\"}",
                    serde_json::to_string(&values.tags).unwrap(),
                ),
            ],
        ));
    }

    fn edit_backend(&mut self) {
        let mut scope = Field::choice(
            "scope",
            "Apply settings to",
            "Every environment always needs a separate state location",
            &["All environments"],
            "All environments",
        );
        scope.kind = FieldKind::Choice(
            std::iter::once("All environments".into())
                .chain(
                    self.project
                        .environments
                        .keys()
                        .filter(|name| {
                            self.loaded.as_ref().is_none_or(|loaded| {
                                !loaded.project.environments.contains_key(*name)
                            })
                        })
                        .cloned(),
                )
                .collect(),
        );
        self.editor = Some(Editor::new(
            "Backend setup",
            EditKind::Backend,
            vec![
                scope,
                Field::choice(
                    "backend",
                    "Backend type",
                    "Local for a quick test; S3 bucket must already exist",
                    &["Local", "S3"],
                    "Local",
                ),
                Field::text(
                    "bucket",
                    "Existing S3 bucket",
                    "State storage is separate from deployment resources",
                    "",
                ),
                Field::text(
                    "backend_region",
                    "Backend AWS region",
                    "Region containing the existing state bucket",
                    "ap-southeast-1",
                ),
                Field::text(
                    "key_pattern",
                    "State key pattern",
                    "Supported placeholders: {project}, {environment}; S3 locking is enabled",
                    "{project}/{environment}/terraform.tfstate",
                ),
            ],
        ));
    }

    fn edit_instance(&mut self, key: Option<String>) {
        let env = &self.project.environments[&self.env_name()];
        let old = key.as_ref().and_then(|k| env.values.instances.get(k));
        let default_key = next_key("web", env.values.instances.keys().map(String::as_str));
        let name = old
            .map(|i| i.name.clone())
            .unwrap_or_else(|| format!("{}-{}", default_key, self.env_name()));
        let source = old
            .map(|i| {
                match (
                    i.existing_security_group_ids.is_empty(),
                    i.security_group_keys.is_empty(),
                ) {
                    (false, false) => "Existing + linked",
                    (true, false) => "Link project",
                    _ => "Use existing",
                }
            })
            .unwrap_or("Use existing");
        let mut identity = Field::text(
            "key",
            "Resource key",
            "Stable Terraform identity; existing keys cannot be renamed in this MVP",
            key.clone().unwrap_or(default_key),
        );
        identity.locked = key.is_some();
        self.editor = Some(Editor::new(
            if key.is_some() {
                "Edit EC2 instance"
            } else {
                "Add EC2 instance"
            },
            EditKind::Instance(key),
            vec![
                identity,
                Field::text(
                    "name",
                    "AWS Name tag",
                    "Changing this value keeps the Terraform resource key unchanged",
                    name,
                ),
                Field::text(
                    "ami",
                    "AMI ID",
                    "Existing AMI; verify its region and instance architecture with AWS/Terraform",
                    old.map(|i| i.ami_id.as_str()).unwrap_or(""),
                ),
                Field::text(
                    "instance_type",
                    "Instance type",
                    "Example: t3.micro; this MVP does not query AWS compatibility",
                    old.map(|i| i.instance_type.as_str()).unwrap_or("t3.micro"),
                ),
                Field::text(
                    "subnet",
                    "Existing subnet ID",
                    "Referenced with data.aws_subnet; the subnet is not adopted",
                    old.map(|i| i.subnet_id.as_str()).unwrap_or(""),
                ),
                Field::choice(
                    "sg_source",
                    "Security group source",
                    "Reference existing IDs, create a new SG, or link managed SG keys",
                    &[
                        "Use existing",
                        "Create new",
                        "Link project",
                        "Existing + linked",
                    ],
                    source,
                ),
                Field::text(
                    "existing_sg_ids",
                    "Existing SG IDs",
                    "Comma-separated IDs; referenced with data.aws_security_group",
                    old.map(|i| i.existing_security_group_ids.join(", "))
                        .unwrap_or_default(),
                ),
                Field::text(
                    "sg_keys",
                    "Project SG keys",
                    "Comma-separated keys from the Security Groups list in this environment",
                    old.map(|i| i.security_group_keys.join(", "))
                        .unwrap_or_default(),
                ),
                Field::text(
                    "new_sg_key",
                    "New SG resource key",
                    "Blank derives <instance_key>_sg; must not overwrite an existing SG",
                    "",
                ),
                Field::text(
                    "new_sg_name",
                    "New SG AWS name",
                    "Blank derives <instance_name>-sg",
                    "",
                ),
                Field::toggle(
                    "new_sg_ingress",
                    "Add a TCP ingress rule",
                    "Off creates no inbound rules; outbound IPv4 is enabled",
                    false,
                ),
                Field::text(
                    "new_sg_port",
                    "TCP ingress port",
                    "Required only when the ingress rule is enabled",
                    "443",
                ),
                Field::text(
                    "new_sg_cidr",
                    "Allowed IPv4 CIDR",
                    "Choose the network permitted to reach this port",
                    "10.0.0.0/16",
                ),
                Field::text(
                    "volume",
                    "Root volume size (GiB)",
                    "Encrypted gp3 volume; positive integer",
                    old.map(|i| i.root_volume_gib.to_string())
                        .unwrap_or_else(|| "20".into()),
                ),
                Field::toggle(
                    "public_ip",
                    "Associate public IPv4",
                    "Routing/IGW must support internet access; no routes are generated",
                    old.is_some_and(|i| i.associate_public_ip),
                ),
                Field::text(
                    "tags",
                    "Instance tags (JSON)",
                    "Merged with default tags; Name is set from AWS Name tag",
                    old.map(|i| serde_json::to_string(&i.tags).unwrap())
                        .unwrap_or_else(|| "{}".into()),
                ),
            ],
        ));
    }

    fn edit_security_group(&mut self, key: Option<String>) {
        let env = &self.project.environments[&self.env_name()];
        let old = key.as_ref().and_then(|k| env.values.security_groups.get(k));
        let rule = old.and_then(|g| g.ingress.get("application"));
        let default_key = next_key(
            "shared_sg",
            env.values.security_groups.keys().map(String::as_str),
        );
        let mut identity = Field::text(
            "key",
            "Resource key",
            "Stable Terraform identity; reusable by several EC2 instances",
            key.clone().unwrap_or(default_key.clone()),
        );
        identity.locked = key.is_some();
        self.editor = Some(Editor::new(
            if key.is_some() {
                "Edit managed security group"
            } else {
                "Add managed security group"
            },
            EditKind::SecurityGroup(key),
            vec![
                identity,
                Field::text(
                    "name",
                    "AWS name",
                    "Name for the managed SG",
                    old.map(|g| g.name.clone())
                        .unwrap_or_else(|| format!("{default_key}-{}", self.env_name())),
                ),
                Field::text(
                    "description",
                    "Description",
                    "Description of this managed security group",
                    old.map(|g| g.description.as_str())
                        .unwrap_or("Managed by EasyTF"),
                ),
                Field::text(
                    "subnet",
                    "Existing subnet ID",
                    "Its VPC is read from data.aws_subnet",
                    old.map(|g| g.subnet_id.as_str()).unwrap_or(""),
                ),
                Field::toggle(
                    "ingress_enabled",
                    "Application ingress rule",
                    "Other rules loaded from tfvars are preserved",
                    rule.is_some(),
                ),
                Field::choice(
                    "protocol",
                    "Application protocol",
                    "TCP, UDP, or all IP protocols",
                    &["tcp", "udp", "-1"],
                    rule.map(|r| r.protocol.as_str()).unwrap_or("tcp"),
                ),
                Field::text(
                    "from_port",
                    "From port",
                    "Start of allowed port range",
                    rule.and_then(|r| r.from_port).unwrap_or(443).to_string(),
                ),
                Field::text(
                    "to_port",
                    "To port",
                    "End of allowed port range",
                    rule.and_then(|r| r.to_port).unwrap_or(443).to_string(),
                ),
                Field::text(
                    "cidr",
                    "Allowed IPv4 CIDR",
                    "Network address and prefix, such as 10.0.0.0/16",
                    rule.map(|r| r.cidr_ipv4.as_str()).unwrap_or("10.0.0.0/16"),
                ),
                Field::toggle(
                    "egress",
                    "Allow all outbound IPv4",
                    "Controls the all_ipv4 rule; other loaded egress rules are preserved",
                    old.map(|g| g.egress.contains_key("all_ipv4"))
                        .unwrap_or(true),
                ),
                Field::text(
                    "tags",
                    "SG tags (JSON)",
                    "Resource-specific tags",
                    old.map(|g| serde_json::to_string(&g.tags).unwrap())
                        .unwrap_or_else(|| "{}".into()),
                ),
            ],
        ));
    }

    fn commit_editor(&mut self, advance: bool) {
        let editor = self.editor.as_ref().unwrap().clone();
        let result = self.apply_editor(&editor, true);
        match result {
            Ok(()) => {
                self.editor = None;
                self.status(
                    "Form saved to the working draft. Review before generating files.",
                    false,
                );
                match editor.kind {
                    EditKind::Project if advance => self.go(Stage::Environments),
                    EditKind::Backend if advance => self.go(Stage::Resources),
                    _ => {}
                }
                self.save_draft();
            }
            Err(error) => self.status(error.to_string(), true),
        }
    }

    fn apply_editor(&mut self, editor: &Editor, validate: bool) -> Result<()> {
        let mut candidate = self.project.clone();
        let mut output = self.output.clone();
        match &editor.kind {
            EditKind::Project => {
                model::validate_key(editor.get("name"), "Project name")?;
                if editor.get("path").trim().is_empty() {
                    bail!("Output folder is required");
                }
                candidate.name = editor.get("name").into();
                output = expand_path(editor.get("path"))?;
            }
            EditKind::Open => {
                let path = expand_path(editor.get("path"))?;
                let loaded = project::load(&path)?;
                self.project = loaded.project.clone();
                self.output = path;
                self.loaded = Some(loaded);
                self.environment_options = self.project.environments.keys().cloned().collect();
                self.env_index = 0;
                self.selected = 0;
                self.stage = Stage::Resources;
                self.dirty = false;
                return Ok(());
            }
            EditKind::Resume => {
                let (draft, output) = project::load_draft(&expand_path(editor.get("path"))?)?;
                let loaded = if output.join(".easytf.toml").exists() {
                    Some(project::load(&output)?)
                } else {
                    None
                };
                self.project = draft;
                self.output = output;
                self.loaded = loaded;
                self.environment_options = self.project.environments.keys().cloned().collect();
                for name in ["dev", "staging", "prod"] {
                    if !self.environment_options.iter().any(|s| s == name) {
                        self.environment_options.push(name.into());
                    }
                }
                self.env_index = 0;
                self.selected = 0;
                self.stage = Stage::Resources;
                self.dirty = true;
                return Ok(());
            }
            EditKind::AddEnvironment => {
                let name = editor.get("name");
                model::validate_key(name, "Environment name")?;
                if candidate.environments.contains_key(name) {
                    bail!("Environment '{name}' already exists");
                }
                let mut env = Environment::default();
                env.values
                    .tags
                    .insert("Project".into(), candidate.name.clone());
                env.values.tags.insert("Environment".into(), name.into());
                candidate.environments.insert(name.into(), env);
                if !self.environment_options.iter().any(|n| n == name) {
                    self.environment_options.push(name.into());
                }
            }
            EditKind::Environment(name) => {
                if editor.get("region").trim().is_empty() {
                    bail!("AWS region is required");
                }
                let env = candidate.environments.get_mut(name).unwrap();
                env.values.aws_region = editor.get("region").into();
                env.values.aws_profile = if editor.get("profile").trim().is_empty() {
                    None
                } else {
                    Some(editor.get("profile").into())
                };
                env.values.tags = serde_json::from_str(editor.get("tags"))?;
            }
            EditKind::Backend => {
                for (name, env) in &mut candidate.environments {
                    if self
                        .loaded
                        .as_ref()
                        .is_some_and(|loaded| loaded.project.environments.contains_key(name))
                    {
                        continue;
                    }
                    if editor.get("scope") != "All environments" && editor.get("scope") != name {
                        continue;
                    }
                    env.backend = if editor.get("backend") == "Local" {
                        Backend::Local
                    } else {
                        let key = editor
                            .get("key_pattern")
                            .replace("{project}", &candidate.name)
                            .replace("{environment}", name);
                        if key.contains('{') || key.contains('}') {
                            bail!(
                                "State key supports only {project} and {environment} placeholders",
                                project = "{project}",
                                environment = "{environment}"
                            );
                        }
                        Backend::S3 {
                            bucket: editor.get("bucket").into(),
                            key,
                            region: editor.get("backend_region").into(),
                            use_lockfile: true,
                        }
                    };
                }
            }
            EditKind::Instance(original) => {
                let env_name = self.env_name();
                let env = candidate.environments.get_mut(&env_name).unwrap();
                let key = editor.get("key");
                model::validate_key(key, "Instance key")?;
                if original.is_none() && env.values.instances.contains_key(key) {
                    bail!("Instance key '{key}' already exists");
                }
                let mut instance = Instance {
                    name: editor.get("name").into(),
                    ami_id: editor.get("ami").into(),
                    instance_type: editor.get("instance_type").into(),
                    subnet_id: editor.get("subnet").into(),
                    existing_security_group_ids: vec![],
                    security_group_keys: vec![],
                    root_volume_gib: editor
                        .get("volume")
                        .parse()
                        .map_err(|_| anyhow::anyhow!("Root volume must be a positive integer"))?,
                    associate_public_ip: editor.get("public_ip") == "true",
                    tags: serde_json::from_str(editor.get("tags"))?,
                };
                match editor.get("sg_source") {
                    "Use existing" => {
                        instance.existing_security_group_ids =
                            comma_list(editor.get("existing_sg_ids"))
                    }
                    "Link project" => {
                        instance.security_group_keys = comma_list(editor.get("sg_keys"))
                    }
                    "Existing + linked" => {
                        instance.existing_security_group_ids =
                            comma_list(editor.get("existing_sg_ids"));
                        instance.security_group_keys = comma_list(editor.get("sg_keys"));
                    }
                    "Create new" => {
                        let sg_key = if editor.get("new_sg_key").is_empty() {
                            format!("{key}_sg")
                        } else {
                            editor.get("new_sg_key").into()
                        };
                        model::validate_key(&sg_key, "Security group key")?;
                        if env.values.security_groups.contains_key(&sg_key) {
                            bail!("Security group '{sg_key}' already exists. Choose Link project or a new key");
                        }
                        let mut ingress = BTreeMap::new();
                        if editor.get("new_sg_ingress") == "true" {
                            let port = editor
                                .get("new_sg_port")
                                .parse::<u16>()
                                .map_err(|_| anyhow::anyhow!("TCP ingress port must be 0–65535"))?;
                            ingress.insert(
                                "application".into(),
                                Rule {
                                    protocol: "tcp".into(),
                                    from_port: Some(port),
                                    to_port: Some(port),
                                    cidr_ipv4: editor.get("new_sg_cidr").into(),
                                    description: "Allow application traffic".into(),
                                },
                            );
                        }
                        let sg = SecurityGroup {
                            name: if editor.get("new_sg_name").is_empty() {
                                format!("{}-sg", instance.name)
                            } else {
                                editor.get("new_sg_name").into()
                            },
                            description: "Managed by EasyTF".into(),
                            subnet_id: instance.subnet_id.clone(),
                            ingress,
                            egress: model::default_egress(),
                            tags: BTreeMap::new(),
                        };
                        env.values.security_groups.insert(sg_key.clone(), sg);
                        instance.security_group_keys.push(sg_key);
                    }
                    _ => bail!("Select a security group source"),
                }
                env.values.instances.insert(key.into(), instance);
            }
            EditKind::SecurityGroup(original) => {
                let env_name = self.env_name();
                let env = candidate.environments.get_mut(&env_name).unwrap();
                let key = editor.get("key");
                model::validate_key(key, "Security group key")?;
                if original.is_none() && env.values.security_groups.contains_key(key) {
                    bail!("Security group key '{key}' already exists");
                }
                let mut sg = env
                    .values
                    .security_groups
                    .get(key)
                    .cloned()
                    .unwrap_or_else(|| SecurityGroup {
                        name: String::new(),
                        description: String::new(),
                        subnet_id: String::new(),
                        ingress: BTreeMap::new(),
                        egress: BTreeMap::new(),
                        tags: BTreeMap::new(),
                    });
                sg.name = editor.get("name").into();
                sg.description = editor.get("description").into();
                sg.subnet_id = editor.get("subnet").into();
                sg.tags = serde_json::from_str(editor.get("tags"))?;
                if editor.get("ingress_enabled") == "true" {
                    let all = editor.get("protocol") == "-1";
                    sg.ingress.insert(
                        "application".into(),
                        Rule {
                            protocol: editor.get("protocol").into(),
                            from_port: if all {
                                None
                            } else {
                                Some(
                                    editor.get("from_port").parse::<u16>().map_err(|_| {
                                        anyhow::anyhow!("From port must be 0–65535")
                                    })?,
                                )
                            },
                            to_port: if all {
                                None
                            } else {
                                Some(
                                    editor
                                        .get("to_port")
                                        .parse::<u16>()
                                        .map_err(|_| anyhow::anyhow!("To port must be 0–65535"))?,
                                )
                            },
                            cidr_ipv4: editor.get("cidr").into(),
                            description: "Allow application traffic".into(),
                        },
                    );
                } else {
                    sg.ingress.remove("application");
                }
                if editor.get("egress") == "true" {
                    sg.egress.extend(model::default_egress());
                } else {
                    sg.egress.remove("all_ipv4");
                }
                env.values.security_groups.insert(key.into(), sg);
            }
        }
        if validate {
            candidate.validate()?;
        }
        self.output = output;
        self.project = candidate;
        self.dirty = true;
        Ok(())
    }

    fn save_draft(&mut self) {
        match project::save_draft(
            &self.draft_path,
            &self.project,
            &self.output,
            self.loaded.as_ref(),
        ) {
            Ok(()) => self.status(
                format!(
                    "Draft saved · {} · Terraform files unchanged",
                    self.draft_path.display()
                ),
                false,
            ),
            Err(e) => self.status(format!("Cannot save draft: {e}"), true),
        }
    }

    fn handle_modal(&mut self, key: KeyEvent) {
        if key.code == KeyCode::Esc || key.code == KeyCode::Char('n') {
            self.modal = None;
            return;
        }
        if matches!(self.modal, Some(Modal::Help)) {
            if key.code == KeyCode::Enter
                || key.code == KeyCode::Char('?')
                || key.code == KeyCode::F(1)
            {
                self.modal = None;
            }
            return;
        }
        if key.code != KeyCode::Enter && key.code != KeyCode::Char('y') {
            return;
        }
        match self.modal.take().unwrap() {
            Modal::Generate => {
                match project::publish(&self.output, &self.project, self.loaded.as_ref()) {
                    Ok(loaded) => {
                        self.loaded = Some(loaded);
                        self.dirty = false;
                        self.go(Stage::Done);
                        self.status(
                            format!("Terraform project generated at {}", self.output.display()),
                            false,
                        );
                    }
                    Err(e) => self.status(e.to_string(), true),
                }
            }
            Modal::Quit => {
                if self.dirty {
                    self.save_draft();
                }
                self.quit = true;
            }
            Modal::Remove(row) => {
                let env_name = self.env_name();
                let env = self.project.environments.get_mut(&env_name).unwrap();
                match row {
                    ResourceRow::Instance(key) => {
                        env.values.instances.remove(&key);
                        self.dirty = true;
                        self.status("Instance definition removed from draft. Review its Terraform plan before applying.", false);
                    }
                    ResourceRow::SecurityGroup(key) => {
                        let users: Vec<_> = env
                            .values
                            .instances
                            .iter()
                            .filter(|(_, i)| i.security_group_keys.contains(&key))
                            .map(|(k, _)| k.clone())
                            .collect();
                        if !users.is_empty() {
                            self.status(
                                format!(
                                    "Cannot remove '{key}': referenced by {}",
                                    users.join(", ")
                                ),
                                true,
                            );
                        } else {
                            env.values.security_groups.remove(&key);
                            self.dirty = true;
                            self.status("SG definition removed from draft. Review its Terraform plan before applying.", false);
                        }
                    }
                }
                self.selected = self.selected.min(self.rows().len().saturating_sub(1));
            }
            Modal::Help => {}
        }
    }

    pub fn draw(&self, frame: &mut Frame) {
        let area = frame.area();
        self.screen_width.set(area.width);
        if area.width < 60 || area.height < 16 {
            frame.render_widget(Paragraph::new("EasyTF\n\nTerminal too small. Resize to at least 60 × 16.\n\nYour draft is preserved. Ctrl+C / q exits.")
                .wrap(Wrap { trim: false }), area);
            if self.modal.is_some() {
                self.draw_modal(frame);
            }
            return;
        }
        let [header, body, status, footer] = Layout::vertical([
            Constraint::Length(4),
            Constraint::Min(8),
            Constraint::Length(3),
            Constraint::Length(2),
        ])
        .areas(area);
        let env_name = self.env_name();
        let context = self
            .project
            .environments
            .get(&env_name)
            .map(|env| {
                let backend = match &env.backend {
                    Backend::Local => "Local state".into(),
                    Backend::S3 { bucket, key, .. } => format!("S3 · {bucket}/{key}"),
                };
                format!(
                    "{env_name}  │  {}  │  Profile: {}  │  {backend}",
                    env.values.aws_region,
                    env.values
                        .aws_profile
                        .as_deref()
                        .unwrap_or("default credential chain")
                )
            })
            .unwrap_or_else(|| "Select an environment to continue".into());
        frame.render_widget(
            Paragraph::new(vec![
                Line::from(vec![
                    Span::styled(
                        " EASYTF ",
                        Style::default()
                            .fg(self.color(Color::Black))
                            .bg(self.color(Color::Cyan))
                            .add_modifier(Modifier::BOLD),
                    ),
                    Span::raw(format!(
                        "  {}  /  {}",
                        self.project.name,
                        self.stage.label()
                    )),
                    Span::styled(
                        "   v0.1.0",
                        Style::default().fg(self.color(Color::DarkGray)),
                    ),
                ]),
                Line::from(Span::styled(
                    context,
                    Style::default().fg(self.color(Color::Gray)),
                )),
                Line::from(Span::styled(
                    format!("Output: {}", self.output.display()),
                    Style::default().fg(self.color(Color::DarkGray)),
                )),
            ]),
            header,
        );
        if self.stage == Stage::Welcome {
            self.draw_welcome(frame, body);
        } else if self.stage == Stage::Done {
            self.draw_done(frame, body);
        } else {
            let wide = body.width >= 110;
            let columns = if wide {
                Layout::horizontal([
                    Constraint::Length(23),
                    Constraint::Percentage(45),
                    Constraint::Min(28),
                ])
                .split(body)
            } else {
                Layout::horizontal([Constraint::Length(20), Constraint::Min(35)]).split(body)
            };
            self.draw_sidebar(frame, columns[0]);
            if let Some(editor) = &self.editor {
                self.draw_editor(frame, columns[1], editor);
                if wide {
                    self.draw_preview(frame, columns[2]);
                }
            } else {
                match self.stage {
                    Stage::Environments => self.draw_environments(frame, columns[1]),
                    Stage::Backend => self.draw_backend(frame, columns[1]),
                    Stage::Resources if !wide && self.compact_preview => {
                        self.draw_preview(frame, columns[1])
                    }
                    Stage::Resources => self.draw_resources(frame, columns[1]),
                    Stage::Review if !wide && self.compact_review_diff => {
                        self.draw_preview(frame, columns[1])
                    }
                    Stage::Review => self.draw_review(frame, columns[1]),
                    Stage::Project => frame.render_widget(
                        Paragraph::new("Press Enter to edit project settings")
                            .block(self.block(" Project ", true)),
                        columns[1],
                    ),
                    _ => {}
                }
                if wide {
                    self.draw_preview(frame, columns[2]);
                }
            }
        }
        let message_color = if self.error {
            Color::Red
        } else if self.stage == Stage::Done {
            Color::Green
        } else {
            Color::Yellow
        };
        frame.render_widget(
            Paragraph::new(self.message.as_str())
                .style(Style::default().fg(self.color(message_color)))
                .wrap(Wrap { trim: false })
                .block(
                    Block::default()
                        .borders(Borders::TOP)
                        .border_style(Style::default().fg(self.color(Color::DarkGray))),
                ),
            status,
        );
        let hints = if self.editor.is_some() {
            "Enter Next / Finish   Tab Fields   ←→ Choice   Ctrl+N Finish   Ctrl+S Save   Esc Cancel"
        } else {
            match self.stage {
                Stage::Welcome => "↑↓ Select   Enter Open   ? Help   q Quit",
                Stage::Environments => "Space Select   Enter Settings   a Add   Ctrl+N Continue   Esc Back   ? Help",
                Stage::Resources => "a Add EC2   s Add SG   Enter Edit   d Remove   [/] Env   r Review   p Preview   ? Help",
                Stage::Review => "↑↓ File   Enter Diff   PgUp/PgDn Scroll   g Generate files   Esc Back   ? Help",
                Stage::Done => "Enter Return to workspace   q Quit",
                _ => "Enter Edit   Ctrl+N Continue   Esc Back   ? Help",
            }
        };
        frame.render_widget(
            Paragraph::new(hints)
                .style(Style::default().fg(self.color(Color::Cyan)))
                .wrap(Wrap { trim: false }),
            footer,
        );
        if self.editor.is_some() && matches!(self.stage, Stage::Welcome | Stage::Done) {
            let rect = centered(body, 85, 14);
            frame.render_widget(Clear, rect);
            self.draw_editor(frame, rect, self.editor.as_ref().unwrap());
        }
        if self.modal.is_some() {
            self.draw_modal(frame);
        }
    }

    fn block<'a>(&self, title: &'a str, active: bool) -> Block<'a> {
        Block::bordered()
            .title(title)
            .border_style(Style::default().fg(self.color(if active {
                Color::Cyan
            } else {
                Color::DarkGray
            })))
    }

    fn draw_welcome(&self, frame: &mut Frame, area: Rect) {
        let [intro, menu, note] = Layout::vertical([
            Constraint::Length(5),
            Constraint::Length(9),
            Constraint::Min(1),
        ])
        .areas(centered(area, 90, area.height));
        frame.render_widget(
            Paragraph::new(vec![
                Line::from(Span::styled(
                    "Terraform, with a terminal workspace.",
                    Style::default()
                        .fg(self.color(Color::Cyan))
                        .add_modifier(Modifier::BOLD),
                )),
                Line::from("Build an AWS project, choose environments, and connect resources."),
                Line::from("Existing subnets and security groups stay references."),
                Line::from("Review generated files before publishing them."),
            ])
            .wrap(Wrap { trim: false }),
            intro,
        );
        let items = [
            "New project",
            "Open existing EasyTF project",
            "Resume saved draft",
            "Explore demo workspace",
        ];
        let mut state = ListState::default().with_selected(Some(self.selected));
        frame.render_stateful_widget(
            List::new(items.into_iter().map(ListItem::new).collect::<Vec<_>>())
                .block(self.block(" Get started ", true))
                .highlight_style(
                    Style::default()
                        .fg(self.color(Color::Cyan))
                        .add_modifier(Modifier::BOLD),
                )
                .highlight_symbol(" > "),
            menu,
            &mut state,
        );
        frame.render_widget(Paragraph::new("MVP · Rust / Ratatui · Keyboard-first\n\nNew projects, EC2, existing network IDs, managed/shared security groups,\nlocal/S3 backends, environment tfvars, and protected file generation.\n\nNo AWS credentials are required to generate files.")
            .style(Style::default().fg(self.color(Color::Gray))).wrap(Wrap { trim: false }), note);
    }

    fn draw_sidebar(&self, frame: &mut Frame, area: Rect) {
        let stages = [
            Stage::Project,
            Stage::Environments,
            Stage::Backend,
            Stage::Resources,
            Stage::Review,
        ];
        let mut lines = vec![
            Line::from(Span::styled(
                " WORKFLOW",
                Style::default()
                    .fg(self.color(Color::Gray))
                    .add_modifier(Modifier::BOLD),
            )),
            Line::from(""),
        ];
        for (i, stage) in stages.into_iter().enumerate() {
            let active = self.stage == stage;
            lines.push(Line::from(Span::styled(
                format!(
                    " {} {}. {}",
                    if active { ">" } else { " " },
                    i + 1,
                    stage.label()
                ),
                Style::default()
                    .fg(self.color(if active { Color::Cyan } else { Color::Gray }))
                    .add_modifier(if active {
                        Modifier::BOLD
                    } else {
                        Modifier::empty()
                    }),
            )));
        }
        lines.extend([Line::from(""), Line::from(" ENVIRONMENTS"), Line::from("")]);
        for name in self.environment_names() {
            lines.push(Line::from(Span::styled(
                format!(
                    " {} {name}",
                    if name == self.env_name() {
                        "●"
                    } else {
                        "○"
                    }
                ),
                Style::default().fg(self.color(if name == self.env_name() {
                    Color::Cyan
                } else {
                    Color::DarkGray
                })),
            )));
        }
        lines.extend([
            Line::from(""),
            Line::from(if self.dirty {
                " DRAFT MODIFIED"
            } else {
                " DRAFT CLEAN"
            }),
            Line::from(" FILES ONLY"),
        ]);
        frame.render_widget(
            Paragraph::new(lines).block(self.block(" Workspace ", false)),
            area,
        );
    }

    fn draw_environments(&self, frame: &mut Frame, area: Rect) {
        let items: Vec<_> = self
            .environment_options
            .iter()
            .map(|name| {
                let selected = self.project.environments.contains_key(name);
                let value = self
                    .project
                    .environments
                    .get(name)
                    .map(|e| {
                        format!(
                            "{} · {}",
                            e.values.aws_region,
                            e.values
                                .aws_profile
                                .as_deref()
                                .unwrap_or("default credentials")
                        )
                    })
                    .unwrap_or_else(|| "Not selected".into());
                ListItem::new(vec![
                    Line::from(format!(" [{}] {name}", if selected { "x" } else { " " })),
                    Line::from(Span::styled(
                        format!("     {value}"),
                        Style::default().fg(self.color(Color::DarkGray)),
                    )),
                    Line::from(""),
                ])
            })
            .collect();
        let mut state = ListState::default().with_selected(Some(self.selected));
        frame.render_stateful_widget(
            List::new(items)
                .block(self.block(" Select environments ", true))
                .highlight_symbol(" > ")
                .highlight_style(
                    Style::default()
                        .fg(self.color(Color::Cyan))
                        .add_modifier(Modifier::BOLD),
                ),
            area,
            &mut state,
        );
    }

    fn draw_backend(&self, frame: &mut Frame, area: Rect) {
        let mut lines = vec![
            Line::from("Existing backend configurations are preserved."),
            Line::from("Backend migration/reconfiguration is outside this MVP."),
            Line::from(""),
        ];
        for (name, env) in &self.project.environments {
            lines.push(Line::from(Span::styled(
                name,
                Style::default().fg(self.color(Color::Cyan)),
            )));
            lines.push(Line::from(match &env.backend {
                Backend::Local => "Local state in the environment folder".into(),
                Backend::S3 {
                    bucket,
                    key,
                    region,
                    ..
                } => format!("S3: {bucket}/{key}\nRegion: {region}"),
            }));
            lines.push(Line::from(""));
        }
        frame.render_widget(
            Paragraph::new(lines)
                .wrap(Wrap { trim: false })
                .block(self.block(" Backend ", true)),
            area,
        );
    }

    fn draw_resources(&self, frame: &mut Frame, area: Rect) {
        let rows = self.rows();
        if rows.is_empty() {
            frame.render_widget(Paragraph::new("No resources yet.\n\nPress a to add an EC2 instance.\nPress s to add a reusable security group.\n\nEC2 accepts existing subnet IDs and either existing\nSG IDs or managed SG keys.\n\nSwitch environments with [ and ].")
                .wrap(Wrap { trim: false }).block(self.block(" Resources ", true)), area);
            return;
        }
        let env_name = self.env_name();
        let env = &self.project.environments[&env_name];
        let items: Vec<_> = rows
            .iter()
            .map(|row| match row {
                ResourceRow::Instance(key) => {
                    let i = &env.values.instances[key];
                    ListItem::new(vec![
                        Line::from(vec![
                            Span::styled(" EC2 ", Style::default().fg(self.color(Color::Cyan))),
                            Span::raw(key),
                        ]),
                        Line::from(Span::styled(
                            format!("     {} · {}", i.name, i.instance_type),
                            Style::default().fg(self.color(Color::Gray)),
                        )),
                        Line::from(Span::styled(
                            format!("     Subnet: {}", i.subnet_id),
                            Style::default().fg(self.color(Color::Gray)),
                        )),
                        Line::from(""),
                    ])
                }
                ResourceRow::SecurityGroup(key) => {
                    let sg = &env.values.security_groups[key];
                    let users = env
                        .values
                        .instances
                        .values()
                        .filter(|i| i.security_group_keys.contains(key))
                        .count();
                    ListItem::new(vec![
                        Line::from(vec![
                            Span::styled(" SG  ", Style::default().fg(self.color(Color::Magenta))),
                            Span::raw(key),
                        ]),
                        Line::from(Span::styled(
                            format!("     {} · linked by {users} instance(s)", sg.name),
                            Style::default().fg(self.color(Color::Gray)),
                        )),
                        Line::from(Span::styled(
                            format!(
                                "     {} ingress / {} egress rules",
                                sg.ingress.len(),
                                sg.egress.len()
                            ),
                            Style::default().fg(self.color(Color::DarkGray)),
                        )),
                        Line::from(""),
                    ])
                }
            })
            .collect();
        let mut state = ListState::default().with_selected(Some(self.selected.min(rows.len() - 1)));
        frame.render_stateful_widget(
            List::new(items)
                .block(self.block(" Resources · a: EC2 / s: SG ", true))
                .highlight_symbol(" > ")
                .highlight_style(
                    Style::default()
                        .bg(self.color(Color::Rgb(25, 37, 49)))
                        .add_modifier(Modifier::BOLD),
                ),
            area,
            &mut state,
        );
    }

    fn draw_editor(&self, frame: &mut Frame, area: Rect, editor: &Editor) {
        let title = format!(" {} ", editor.title);
        let block = self.block(&title, true);
        let inner = block.inner(area);
        frame.render_widget(block, area);
        if inner.height < 4 {
            return;
        }
        let [fields_area, help_area] =
            Layout::vertical([Constraint::Min(1), Constraint::Length(3)]).areas(inner);
        let visible = editor.visible();
        let selected_pos = visible
            .iter()
            .position(|i| *i == editor.selected)
            .unwrap_or(0);
        let capacity = (fields_area.height / 3).max(1) as usize;
        let start = selected_pos.saturating_sub(capacity - 1);
        for (row, index) in visible.iter().skip(start).take(capacity).enumerate() {
            let field = &editor.fields[*index];
            let active = *index == editor.selected;
            let y = fields_area.y + row as u16 * 3;
            let width = fields_area.width.saturating_sub(2);
            let label = format!(
                "{}{}",
                field.label,
                if field.locked { " [locked]" } else { "" }
            );
            frame.render_widget(
                Paragraph::new(label).style(Style::default().fg(self.color(if active {
                    Color::Cyan
                } else {
                    Color::Gray
                }))),
                Rect::new(fields_area.x + 1, y, width, 1),
            );
            let prefix = match field.kind {
                FieldKind::Toggle => {
                    if field.value == "true" {
                        "[x] "
                    } else {
                        "[ ] "
                    }
                }
                FieldKind::Choice(_) => "‹ ",
                FieldKind::Text => "",
            };
            let suffix = if matches!(field.kind, FieldKind::Choice(_)) {
                " ›"
            } else {
                ""
            };
            let content_width = width.saturating_sub(2) as usize;
            let mut start_char = 0;
            if active && matches!(field.kind, FieldKind::Text) {
                while UnicodeWidthStr::width(
                    field
                        .value
                        .chars()
                        .skip(start_char)
                        .take(editor.cursor.saturating_sub(start_char))
                        .collect::<String>()
                        .as_str(),
                ) >= content_width
                    && start_char < editor.cursor
                {
                    start_char += 1;
                }
            }
            let text: String = field.value.chars().skip(start_char).collect();
            frame.render_widget(
                Paragraph::new(format!("{prefix}{text}{suffix}")).style(
                    Style::default()
                        .fg(self.color(if field.locked {
                            Color::Gray
                        } else {
                            Color::White
                        }))
                        .bg(self.color(if active {
                            Color::Rgb(25, 37, 49)
                        } else {
                            Color::Reset
                        })),
                ),
                Rect::new(fields_area.x + 1, y + 1, width, 1),
            );
            if active && !field.locked && matches!(field.kind, FieldKind::Text) {
                let before: String = field
                    .value
                    .chars()
                    .skip(start_char)
                    .take(editor.cursor.saturating_sub(start_char))
                    .collect();
                let x = fields_area.x
                    + 1
                    + UnicodeWidthStr::width(before.as_str()).min(content_width.saturating_sub(1))
                        as u16;
                frame.set_cursor_position((x, y + 1));
            }
        }
        frame.render_widget(
            Paragraph::new(editor.fields[editor.selected].help)
                .style(Style::default().fg(self.color(Color::Yellow)))
                .wrap(Wrap { trim: false })
                .block(
                    Block::default()
                        .borders(Borders::TOP)
                        .border_style(Style::default().fg(self.color(Color::DarkGray))),
                ),
            help_area,
        );
    }

    fn draw_review(&self, frame: &mut Frame, area: Rect) {
        if self.review_files.is_empty() {
            frame.render_widget(Paragraph::new("Project validation failed.\n\nReturn to the workspace and resolve the error shown below.")
            .wrap(Wrap { trim: false }).block(self.block(" Review ", true)), area);
            return;
        }
        let items: Vec<_> = self
            .review_files
            .iter()
            .map(|file| {
                let (symbol, color) = match file.action {
                    "add" => ("+", Color::Green),
                    "update" => ("~", Color::Yellow),
                    _ => ("=", Color::DarkGray),
                };
                ListItem::new(Line::from(vec![
                    Span::styled(
                        format!(" {symbol} "),
                        Style::default().fg(self.color(color)),
                    ),
                    Span::raw(&file.path),
                ]))
            })
            .collect();
        let mut state = ListState::default().with_selected(Some(self.selected));
        frame.render_stateful_widget(
            List::new(items)
                .highlight_symbol(" > ")
                .highlight_style(Style::default().bg(self.color(Color::DarkGray)))
                .block(self.block(" File changes · + add / ~ update / = unchanged ", true)),
            area,
            &mut state,
        );
    }

    fn draw_preview(&self, frame: &mut Frame, area: Rect) {
        let env_name = self.env_name();
        let mut candidate = self.clone();
        if let Some(editor) = &self.editor {
            if !matches!(editor.kind, EditKind::Open | EditKind::Resume) {
                let _ = candidate.apply_editor(editor, false);
            }
        }
        let Some(env) = candidate.project.environments.get(&env_name) else {
            return;
        };
        let (title, lines): (&str, Vec<Line>) = if self.stage == Stage::Review {
            let file = self.review_files.get(self.selected);
            (
                " File diff · PgUp/PgDn ",
                file.map(|f| {
                    diff_lines(f.before.as_deref(), &f.after)
                        .into_iter()
                        .map(|line| {
                            let color = if line.starts_with('+') {
                                Color::Green
                            } else if line.starts_with('-') {
                                Color::Red
                            } else {
                                Color::Gray
                            };
                            Line::from(Span::styled(line, Style::default().fg(self.color(color))))
                        })
                        .collect()
                })
                .unwrap_or_default(),
            )
        } else {
            match self.preview {
                0 => (
                    " TFVARS · F3 switches view ",
                    hcl::to_string(&env.values)
                        .unwrap_or_default()
                        .lines()
                        .map(|line| {
                            let color =
                                if line.trim_start().starts_with('"') || line.contains(" = ") {
                                    Color::Cyan
                                } else {
                                    Color::Gray
                                };
                            Line::from(Span::styled(
                                line.to_string(),
                                Style::default().fg(self.color(color)),
                            ))
                        })
                        .collect(),
                ),
                1 => {
                    let mut lines = vec![Line::from("DEPENDENCIES"), Line::from("")];
                    for (key, i) in &env.values.instances {
                        lines.push(Line::from(Span::styled(
                            format!("EC2 · {key}"),
                            Style::default().fg(self.color(Color::Cyan)),
                        )));
                        lines.push(Line::from(format!("  ← {} [existing subnet]", i.subnet_id)));
                        for id in &i.existing_security_group_ids {
                            lines.push(Line::from(format!("  ← {id} [existing SG]")));
                        }
                        for sg in &i.security_group_keys {
                            lines.push(Line::from(format!("  ← {sg} [managed SG]")));
                        }
                        lines.push(Line::from(""));
                    }
                    lines.push(Line::from(
                        "Existing resources are referenced through data sources.",
                    ));
                    (" Dependencies · F3 switches view ", lines)
                }
                _ => {
                    let mut lines = vec![
                        Line::from("OUTPUT DEFINITIONS"),
                        Line::from("Values become available in Terraform state after apply."),
                        Line::from(""),
                    ];
                    for key in env.values.instances.keys() {
                        lines.push(Line::from(Span::styled(
                            format!("instances.{key}"),
                            Style::default().fg(self.color(Color::Cyan)),
                        )));
                        lines.push(Line::from("  id / private_ip / public_ip"));
                        lines.push(Line::from("  subnet_id / security_group_ids"));
                        lines.push(Line::from("  [Known after apply]"));
                        lines.push(Line::from(""));
                    }
                    lines.push(Line::from("existing_subnets → VPC / availability zone"));
                    lines.push(Line::from("security_groups → ID / primary VPC"));
                    (" Outputs · F3 switches view ", lines)
                }
            }
        };
        frame.render_widget(
            Paragraph::new(lines)
                .block(self.block(title, false))
                .wrap(Wrap { trim: false })
                .scroll((self.preview_scroll, 0)),
            area,
        );
    }

    fn draw_done(&self, frame: &mut Frame, area: Rect) {
        let env_name = self.env_name();
        let init = self
            .project
            .environments
            .get(&env_name)
            .map(|env| {
                if matches!(env.backend, Backend::S3 { .. }) {
                    "terraform init -backend-config=backend.s3.tfbackend"
                } else {
                    "terraform init"
                }
            })
            .unwrap_or("terraform init");
        frame.render_widget(
            Paragraph::new(vec![
                Line::from(Span::styled(
                    "✓ Project generated",
                    Style::default()
                        .fg(self.color(Color::Green))
                        .add_modifier(Modifier::BOLD),
                )),
                Line::from(""),
                Line::from(self.output.to_string_lossy().to_string()),
                Line::from(""),
                Line::from("Each environment has its own root configuration, tfvars, and backend."),
                Line::from("Shared modules contain EC2 and managed security groups."),
                Line::from(""),
                Line::from("NEXT STEPS"),
                Line::from(format!(
                    "cd {}/environments/{env_name}",
                    self.output.display()
                )),
                Line::from(init),
                Line::from("terraform validate"),
                Line::from("terraform plan"),
                Line::from(""),
                Line::from("Existing AWS IDs have not been verified against AWS."),
                Line::from("Generated files have not been applied."),
                Line::from(""),
                Line::from("Press Enter to edit this project again, or q to exit."),
            ])
            .wrap(Wrap { trim: false })
            .block(self.block(" Ready for Terraform review ", true)),
            area,
        );
    }

    fn draw_modal(&self, frame: &mut Frame) {
        let Some(modal) = &self.modal else {
            return;
        };
        let (title, text) = match modal {
            Modal::Help => (" Keyboard help ", "WORKSPACE\n↑/↓ or j/k  Select resource or item\na            Add EC2\ns            Add managed security group\nEnter        Edit selected resource\nd / Delete   Remove definition from draft\n[ / ] / Tab  Switch active environment\ne            Environment settings\nn            Environment selection\nr / Ctrl+N   Review files\np            Switch tfvars / dependencies / outputs\nPgUp/PgDn    Scroll preview\nCtrl+S       Save local draft\n\nFORM\nTab / ↑↓     Select field\n← / →        Change choice or move cursor\nSpace        Toggle checkbox\nCtrl+U       Clear text field\nCtrl+S       Save form to draft\nEnter        Next field; finish at the last field
Ctrl+N       Save form and continue
F1           Help\nEsc          Discard unsaved form changes\n\nText fields accept letters such as q, s, and g normally.\nEnter / Esc closes this help.".into()),
            Modal::Generate => (" Generate files ", format!("Write Terraform configuration to:\n\n{}\n\n{} environment(s) · {} changed file(s)\n\nExisting subnet and SG IDs remain references.\nManual edits and stale file changes block publishing.\nNo Terraform apply or destroy is executed.\n\nEnter / y Generate files     Esc / n Cancel", self.output.display(), self.project.environments.len(), self.review_files.iter().filter(|f| f.action != "unchanged").count())),
            Modal::Remove(row) => (" Remove resource definition ", format!("Remove {} from the draft?\n\nA later Terraform apply may destroy the managed resource.\nReferenced shared security groups remain in the draft.\n\nEnter / y Remove definition     Esc / n Cancel", match row { ResourceRow::Instance(k) => format!("EC2 '{k}'"), ResourceRow::SecurityGroup(k) => format!("SG '{k}'") })),
            Modal::Quit => (" Exit EasyTF ", if self.dirty { "Save the working draft locally and exit?\n\nNo Terraform files will be written.\n\nEnter / y Save draft and exit     Esc / n Stay".into() }
                else { "Exit EasyTF?\n\nEnter / y Exit     Esc / n Stay".into() }),
        };
        let height = if matches!(modal, Modal::Help) { 34 } else { 15 };
        let rect = centered(frame.area(), 86, height);
        frame.render_widget(Clear, rect);
        frame.render_widget(
            Paragraph::new(text)
                .style(Style::default().fg(self.color(Color::White)))
                .wrap(Wrap { trim: false })
                .block(self.block(title, true)),
            rect,
        );
    }
}

pub fn run(app: &mut App) -> Result<()> {
    ratatui::run(|terminal| -> Result<()> {
        crossterm::execute!(std::io::stdout(), event::EnableBracketedPaste)?;
        let result = (|| {
            while !app.quit {
                terminal.draw(|frame| app.draw(frame))?;
                if event::poll(std::time::Duration::from_millis(200))? {
                    app.handle(event::read()?);
                }
            }
            Ok(())
        })();
        let _ = crossterm::execute!(std::io::stdout(), event::DisableBracketedPaste);
        result
    })
}

pub fn expand_path(value: &str) -> Result<PathBuf> {
    let path = if value == "~" || value.starts_with("~/") {
        let home = std::env::var_os("HOME")
            .ok_or_else(|| anyhow::anyhow!("HOME is not available; use an absolute path"))?;
        PathBuf::from(home).join(value.strip_prefix("~/").unwrap_or(""))
    } else {
        PathBuf::from(value)
    };
    Ok(if path.is_absolute() {
        path
    } else {
        std::env::current_dir()?.join(path)
    })
}

fn centered(area: Rect, width: u16, height: u16) -> Rect {
    let width = width.min(area.width);
    let height = height.min(area.height);
    Rect::new(
        area.x + (area.width - width) / 2,
        area.y + (area.height - height) / 2,
        width,
        height,
    )
}

fn comma_list(value: &str) -> Vec<String> {
    let mut values: Vec<_> = value
        .split(',')
        .map(str::trim)
        .filter(|v| !v.is_empty())
        .map(str::to_string)
        .collect();
    values.sort();
    values.dedup();
    values
}

fn next_key<'a>(prefix: &str, keys: impl Iterator<Item = &'a str>) -> String {
    let keys: Vec<_> = keys.collect();
    if !keys.contains(&prefix) {
        return prefix.into();
    }
    (2..)
        .map(|i| format!("{prefix}_{i}"))
        .find(|key| !keys.contains(&key.as_str()))
        .unwrap()
}

fn diff_lines(before: Option<&str>, after: &str) -> Vec<String> {
    let old: Vec<_> = before.unwrap_or("").lines().collect();
    let new: Vec<_> = after.lines().collect();
    if old == new {
        return std::iter::once("No changes".into())
            .chain(new.iter().map(|l| format!(" {l}")))
            .collect();
    }
    let prefix = old.iter().zip(&new).take_while(|(a, b)| a == b).count();
    let suffix = old[prefix..]
        .iter()
        .rev()
        .zip(new[prefix..].iter().rev())
        .take_while(|(a, b)| a == b)
        .count();
    let mut lines: Vec<_> = old[prefix.saturating_sub(3)..prefix]
        .iter()
        .map(|l| format!(" {l}"))
        .collect();
    lines.extend(
        old[prefix..old.len() - suffix]
            .iter()
            .map(|l| format!("-{l}")),
    );
    lines.extend(
        new[prefix..new.len() - suffix]
            .iter()
            .map(|l| format!("+{l}")),
    );
    lines.extend(
        new[new.len() - suffix..]
            .iter()
            .take(3)
            .map(|l| format!(" {l}")),
    );
    lines
}

#[cfg(test)]
mod tests {
    use super::*;
    use ratatui::{backend::TestBackend, Terminal};

    fn key(code: KeyCode) -> Event {
        Event::Key(KeyEvent::new(code, KeyModifiers::NONE))
    }

    #[test]
    fn text_input_does_not_trigger_global_shortcuts() {
        let mut app = App::new(Project::demo(), PathBuf::from("demo"), None, true, false);
        app.handle(key(KeyCode::Char('a')));
        for c in "qsg?".chars() {
            app.handle(key(KeyCode::Char(c)));
        }
        assert!(!app.quit);
        assert!(app.modal.is_none());
        assert!(app.editor.unwrap().get("key").ends_with("qsg?"));
    }

    #[test]
    fn removing_a_shared_security_group_is_blocked() {
        let mut project = Project::demo();
        let env = project.environments.get_mut("dev").unwrap();
        env.values.security_groups.insert(
            "shared".into(),
            SecurityGroup {
                name: "shared".into(),
                description: "Shared".into(),
                subnet_id: "subnet-0123456789abcdef0".into(),
                ingress: BTreeMap::new(),
                egress: model::default_egress(),
                tags: BTreeMap::new(),
            },
        );
        env.values
            .instances
            .get_mut("web_primary")
            .unwrap()
            .security_group_keys
            .push("shared".into());
        let mut app = App::new(project, PathBuf::from("demo"), None, true, false);
        app.modal = Some(Modal::Remove(ResourceRow::SecurityGroup("shared".into())));
        app.handle(key(KeyCode::Enter));
        assert!(app.error);
        assert!(app.project.environments["dev"]
            .values
            .security_groups
            .contains_key("shared"));
    }

    #[test]
    fn responsive_layout_renders_wide_small_and_tiny_terminals() {
        let mut app = App::new(Project::demo(), PathBuf::from("demo"), None, true, true);
        for (width, height) in [(140, 40), (80, 24), (40, 10)] {
            let mut terminal = Terminal::new(TestBackend::new(width, height)).unwrap();
            terminal.draw(|f| app.draw(f)).unwrap();
            let text: String = terminal
                .backend()
                .buffer()
                .content()
                .iter()
                .map(|c| c.symbol())
                .collect();
            assert!(text.contains(if width < 60 { "EasyTF" } else { "EASYTF" }));
        }
        app.handle(key(KeyCode::Char('a')));
        let mut terminal = Terminal::new(TestBackend::new(80, 24)).unwrap();
        terminal.draw(|f| app.draw(f)).unwrap();
        app.modal = Some(Modal::Help);
        terminal.draw(|f| app.draw(f)).unwrap();
    }
    #[test]
    fn wizard_continues_without_function_keys_and_preview_scrolls() {
        let temp = tempfile::tempdir().unwrap();
        let mut app = App::new(
            Project::empty("test-project"),
            temp.path().join("project"),
            None,
            false,
            true,
        );
        app.draft_path = temp.path().join("draft.json");
        app.go(Stage::Project);
        let next = || Event::Key(KeyEvent::new(KeyCode::Char('n'), KeyModifiers::CONTROL));
        app.handle(next());
        assert_eq!(app.stage, Stage::Environments);
        app.handle(key(KeyCode::Down));
        app.handle(key(KeyCode::Char(' ')));
        app.handle(next());
        assert_eq!(app.stage, Stage::Backend);
        app.handle(next());
        assert_eq!(app.stage, Stage::Resources);
        assert!(app.editor.is_none());
        app.screen_width.set(80);
        app.handle(key(KeyCode::Char('p')));
        assert!(app.compact_preview);
        app.handle(key(KeyCode::Down));
        assert_eq!(app.preview_scroll, 1);
        app.handle(key(KeyCode::Esc));
        assert!(!app.compact_preview);
        app.handle(key(KeyCode::Char('r')));
        assert_eq!(app.stage, Stage::Review);
        app.handle(key(KeyCode::Char('g')));
        assert!(matches!(app.modal, Some(Modal::Generate)));
    }
}
