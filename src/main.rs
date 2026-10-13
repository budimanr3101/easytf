use anyhow::{bail, Context, Result};
use clap::{Parser, Subcommand};
use easytf::{model::Project, project, ui};
use std::fs;
use std::io::IsTerminal;
use std::path::PathBuf;

#[derive(Parser)]
#[command(
    name = "easytf",
    version,
    about = "A terminal workspace for generating Terraform projects"
)]
struct Cli {
    #[command(subcommand)]
    command: Option<Command>,
    #[arg(long, global = true, help = "Open an existing EasyTF project")]
    project: Option<PathBuf>,
    #[arg(long, global = true, help = "Terraform project output folder")]
    output: Option<PathBuf>,
    #[arg(long, help = "Explore a prefilled demo with placeholder AWS IDs")]
    demo: bool,
    #[arg(long, global = true, help = "Disable terminal colors")]
    no_color: bool,
}

#[derive(Subcommand)]
enum Command {
    /// Generate a project from a JSON configuration; never runs Terraform apply
    Generate {
        #[arg(long)]
        config: PathBuf,
        #[arg(long)]
        dry_run: bool,
        #[arg(long)]
        json: bool,
    },
    /// Validate local project inputs and generated HCL (does not contact AWS)
    Check {
        #[arg(long)]
        json: bool,
    },
    /// Restore files from an interrupted generation after the owning process exits
    Recover,
    /// Read AWS resources using the selected AWS CLI profile (no writes)
    Discover {
        #[arg(value_enum)]
        kind: easytf::discovery::Kind,
        #[arg(long)]
        region: String,
        #[arg(long)]
        profile: Option<String>,
        #[arg(long, help = "Subnet ID required to filter security groups by VPC")]
        subnet: Option<String>,
    },
    /// Print the demo JSON configuration for scripting or testing
    Example,
    /// Render a deterministic TUI screenshot for development
    #[command(hide = true)]
    Snapshot {
        file: PathBuf,
        #[arg(long, default_value_t = 140)]
        width: u16,
        #[arg(long, default_value_t = 40)]
        height: u16,
        #[arg(long, default_value = "resources")]
        view: String,
    },
}

fn main() {
    if let Err(error) = execute() {
        eprintln!("EasyTF: {error:#}");
        std::process::exit(1);
    }
}

fn execute() -> Result<()> {
    let cli = Cli::parse();
    match cli.command {
        Some(Command::Example) => println!("{}", serde_json::to_string_pretty(&Project::demo())?),
        Some(Command::Generate {
            config,
            dry_run,
            json,
        }) => {
            let project: Project = serde_json::from_str(
                &fs::read_to_string(&config)
                    .with_context(|| format!("Cannot read {}", config.display()))?,
            )?;
            project.validate()?;
            let root = cli.output.unwrap_or_else(|| PathBuf::from(&project.name));
            let root = ui::expand_path(&root.to_string_lossy())?;
            let loaded = if root.join(".easytf.toml").exists() {
                Some(project::load(&root)?)
            } else {
                None
            };
            let changes = project::changes(&root, &project)?;
            if !dry_run {
                project::publish(&root, &project, loaded.as_ref())?;
            }
            if json {
                println!(
                    "{}",
                    serde_json::to_string_pretty(&serde_json::json!({
                        "status": if dry_run { "preview" } else { "generated" },
                        "output": root,
                        "environments": project.environments.keys().collect::<Vec<_>>(),
                        "changes": changes.iter().map(|c| serde_json::json!({"path":c.path,"action":c.action})).collect::<Vec<_>>(),
                        "aws_verified": false,
                        "terraform_applied": false,
                    }))?
                );
            } else {
                println!(
                    "{} · {}",
                    if dry_run { "Preview" } else { "Generated" },
                    root.display()
                );
                for file in &changes {
                    println!("{:9} {}", file.action, file.path);
                }
                println!("\nAWS IDs were not verified. Terraform apply was not executed.");
            }
        }
        Some(Command::Check { json }) => {
            let root = ui::expand_path(
                &cli.project
                    .unwrap_or_else(|| PathBuf::from("."))
                    .to_string_lossy(),
            )?;
            let loaded = project::load(&root)?;
            let files = project::changes(&root, &loaded.project)?;
            let altered: Vec<_> = files
                .iter()
                .filter(|f| f.action != "unchanged")
                .map(|f| &f.path)
                .collect();
            if json {
                println!(
                    "{}",
                    serde_json::to_string_pretty(
                        &serde_json::json!({"healthy":true,"scope":"local-inputs-and-generated-HCL","aws_verified":false,"files_with_pending_changes":altered})
                    )?
                );
            } else {
                println!("Local inputs and generated HCL are valid.\nAWS existence/permissions and Terraform provider validation were not checked.\n{} file(s) differ from the current generated configuration.", altered.len());
            }
        }
        Some(Command::Discover {
            kind,
            region,
            profile,
            subnet,
        }) => {
            let items = easytf::discovery::discover(
                kind,
                &region,
                profile.as_deref(),
                subnet.as_deref(),
                &std::sync::atomic::AtomicBool::new(false),
            )?;
            println!("{}", serde_json::to_string_pretty(&items)?);
        }
        Some(Command::Recover) => {
            let root = ui::expand_path(
                &cli.project
                    .unwrap_or_else(|| PathBuf::from("."))
                    .to_string_lossy(),
            )?;
            let count = project::recover(&root)?;
            println!(
                "Recovery complete · {count} tracked file(s) restored · {}",
                root.display()
            );
        }
        Some(Command::Snapshot {
            file,
            width,
            height,
            view,
        }) => {
            let mut app = ui::App::new(
                Project::demo(),
                PathBuf::from("/projects/payment-infra"),
                None,
                true,
                !cli.no_color,
            );
            match view.as_str() {
                "welcome" => app.stage = ui::Stage::Welcome,
                "form" => app.handle(crossterm::event::Event::Key(
                    crossterm::event::KeyEvent::new(
                        crossterm::event::KeyCode::Enter,
                        crossterm::event::KeyModifiers::NONE,
                    ),
                )),
                "dependencies" => app.handle(crossterm::event::Event::Key(
                    crossterm::event::KeyEvent::new(
                        crossterm::event::KeyCode::F(3),
                        crossterm::event::KeyModifiers::NONE,
                    ),
                )),
                "review" => app.handle(crossterm::event::Event::Key(
                    crossterm::event::KeyEvent::new(
                        crossterm::event::KeyCode::F(2),
                        crossterm::event::KeyModifiers::NONE,
                    ),
                )),
                "resources" => {}
                _ => bail!("Snapshot views: welcome, resources, form, dependencies, review"),
            }
            snapshot(&app, &file, width, height)?;
        }
        None => {
            if !std::io::stdin().is_terminal() || !std::io::stdout().is_terminal() {
                bail!("The TUI requires an interactive terminal. Use `easytf generate --config FILE --output FOLDER` for scripts, or `easytf --help`");
            }
            let candidate = cli.project.or_else(|| {
                std::env::current_dir()
                    .ok()
                    .filter(|p| p.join(".easytf.toml").exists())
            });
            let loaded = candidate.as_ref().map(|p| project::load(p)).transpose()?;
            let project = loaded
                .as_ref()
                .map(|p| p.project.clone())
                .unwrap_or_else(|| {
                    if cli.demo {
                        Project::demo()
                    } else {
                        Project::empty("my-project")
                    }
                });
            let output = candidate.or(cli.output).unwrap_or_else(|| {
                PathBuf::from(if cli.demo {
                    "payment-infra"
                } else {
                    "my-project"
                })
            });
            let output = ui::expand_path(&output.to_string_lossy())?;
            let mut app = ui::App::new(
                project,
                output,
                loaded,
                cli.demo,
                !cli.no_color && std::env::var_os("NO_COLOR").is_none(),
            );
            ui::run(&mut app)?;
        }
    }
    Ok(())
}

fn snapshot(app: &ui::App, file: &std::path::Path, width: u16, height: u16) -> Result<()> {
    use ratatui::{backend::TestBackend, style::Color, Terminal};
    let mut terminal = Terminal::new(TestBackend::new(width, height))?;
    terminal.draw(|f| app.draw(f))?;
    let buffer = terminal.backend().buffer();
    let cell_w = 9;
    let cell_h = 19;
    let margin = 16;
    let mut svg = format!("<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"{}\" height=\"{}\" viewBox=\"0 0 {} {}\"><rect width=\"100%\" height=\"100%\" fill=\"#10141c\"/><g font-family=\"Menlo,monospace\" font-size=\"14\">", width as usize * cell_w + 2*margin, height as usize * cell_h + 2*margin, width as usize * cell_w + 2*margin, height as usize * cell_h + 2*margin);
    let color = |c: Color| -> String {
        match c {
            Color::Black => "#10141c".into(),
            Color::White | Color::Reset => "#e5e9f0".into(),
            Color::Gray => "#aeb8c5".into(),
            Color::DarkGray => "#566273".into(),
            Color::Cyan | Color::LightCyan => "#66d9ef".into(),
            Color::Green | Color::LightGreen => "#98c379".into(),
            Color::Red | Color::LightRed => "#e06c75".into(),
            Color::Yellow | Color::LightYellow => "#e5c07b".into(),
            Color::Magenta | Color::LightMagenta => "#c678dd".into(),
            Color::Blue | Color::LightBlue => "#61afef".into(),
            Color::Rgb(r, g, b) => format!("#{r:02x}{g:02x}{b:02x}"),
            _ => "#aeb8c5".into(),
        }
    };
    for y in 0..height {
        for x in 0..width {
            let cell = &buffer[(x, y)];
            let px = margin + x as usize * cell_w;
            let py = margin + y as usize * cell_h;
            if cell.bg != Color::Reset {
                svg.push_str(&format!("<rect x=\"{px}\" y=\"{py}\" width=\"{cell_w}\" height=\"{cell_h}\" fill=\"{}\"/>",color(cell.bg)));
            }
            if cell.symbol() != " " {
                let text = cell
                    .symbol()
                    .replace('&', "&amp;")
                    .replace('<', "&lt;")
                    .replace('>', "&gt;");
                svg.push_str(&format!(
                    "<text x=\"{px}\" y=\"{}\" fill=\"{}\">{text}</text>",
                    py + 15,
                    color(cell.fg)
                ));
            }
        }
    }
    svg.push_str("</g></svg>");
    fs::write(file, svg)?;
    Ok(())
}
