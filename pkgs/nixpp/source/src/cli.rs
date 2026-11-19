//! The `nixpp` command line.
//!
//! One executable plays three roles:
//!
//! * the guest client (`prepare`, `build`, `rebuild`, `upgrade`, `switch`, `check`,
//!   `list-generations`, `rollback`, `recover`), which talks to the native
//!   controller over a Unix socket;
//! * the native service (`serve`) and the socket-less local controller
//!   (`controller ...`), which run outside the guest;
//! * first-time setup (`init`).

use crate::bootstrap;
use crate::controller;
use crate::error::{Error, Result};
use crate::fsutil::canonical_json;
use crate::guest::{self, ProcessBuilder, Stage};
use crate::runner::SessionRunner;
use crate::server::{self, Served};
use crate::ui::{ColorChoice, Style, Ui};
use anyhow::Context;
use clap::builder::Styles;
use clap::builder::styling::AnsiColor;
use clap::{Args, CommandFactory, Parser, Subcommand};
use serde_json::{Value, json};
use std::io::{self, Write};
use std::path::{Path, PathBuf};
use std::process::ExitCode;

const DEFAULT_SOCKET: &str = "/tmp/nixpp.sock";

fn styles() -> Styles {
    Styles::styled()
        .header(AnsiColor::Green.on_default().bold())
        .usage(AnsiColor::Green.on_default().bold())
        .literal(AnsiColor::Cyan.on_default().bold())
        .placeholder(AnsiColor::Cyan.on_default())
}

/// Manage the Nix system of a TermuxPP guest.
#[derive(Debug, Parser)]
#[command(name = "nixpp", version, styles = styles(), arg_required_else_help = true)]
pub struct Cli {
    /// Native runtime directory
    #[arg(long, global = true, env = "NIXPP_RUNTIME", value_name = "DIR")]
    runtime: Option<PathBuf>,

    /// Management socket (guest default: /tmp/nixpp.sock)
    #[arg(long, global = true, env = "NIXPP_SOCKET", value_name = "PATH")]
    socket: Option<PathBuf>,

    /// Print machine-readable JSON, never colour
    #[arg(long, global = true)]
    json: bool,

    /// Suppress progress and success messages
    #[arg(short, long, global = true)]
    quiet: bool,

    /// When to use colour
    #[arg(long, global = true, value_enum, default_value_t = ColorChoice::Auto, value_name = "WHEN")]
    color: ColorChoice,

    #[command(subcommand)]
    command: Command,
}

#[derive(Debug, Args)]
pub struct BuildArgs {
    /// Flake URI, without an output fragment
    #[arg(long)]
    flake: String,

    /// Host name of the system configuration
    #[arg(long)]
    host: String,

    /// Build on the configured disposable worker
    #[arg(long)]
    rworker: bool,
}

#[derive(Debug, Args, Default)]
pub struct UpgradeArgs {
    /// Override the configured flake URI, without an output fragment
    #[arg(long)]
    flake: Option<String>,

    /// Override the configured host name
    #[arg(long)]
    host: Option<String>,

    /// Build on the configured disposable worker
    #[arg(long, conflicts_with = "dry_run")]
    rworker: bool,

    /// Upgrade from the host's signed binary cache without evaluating the flake
    #[arg(long, conflicts_with_all = ["flake", "host", "rworker"])]
    from_cache: bool,

    /// Show what Nix would build or fetch without activating a generation
    #[arg(long)]
    dry_run: bool,
}

#[derive(Debug, Subcommand)]
#[command(next_display_order = None)]
pub enum Command {
    /// Prepare a candidate without selecting or activating it
    Prepare {
        /// Store path of the system generation
        generation: PathBuf,
    },
    /// Print a shell completion script
    Completions {
        /// Shell to generate completions for
        #[arg(value_enum)]
        shell: clap_complete::Shell,
    },
    /// Build a system remotely and print its store path
    Build(BuildArgs),
    /// Build, prepare and switch to a system
    Rebuild(BuildArgs),
    /// Build and activate the latest configured system
    Upgrade(UpgradeArgs),
    /// Fetch and activate the latest configured system
    Fetch {
        #[arg(value_enum)]
        target: FetchTarget,
    },
    /// Compare system closures (previous to current by default)
    Diff {
        /// Earlier generation number or store basename
        #[arg(requires = "to")]
        from: Option<String>,
        /// Later generation number or store basename
        #[arg(requires = "from")]
        to: Option<String>,
    },
    /// Check the native controller, Nix store, builders and signed cache
    Doctor,
    /// Prune old system generations and collect unreferenced Nix store paths
    Gc {
        /// Minimum number of generations to keep
        #[arg(long, default_value_t = 3, value_parser = clap::value_parser!(u16).range(1..=1000))]
        keep_generations: u16,
        /// Show which generations would be removed
        #[arg(long)]
        dry_run: bool,
    },
    #[command(name = "__cache-pin-obsolete", hide = true)]
    CachePinObsolete { generation: String },
    /// Show the active and previous system generations
    Status {
        /// Show all retained generations
        #[arg(long)]
        all: bool,
    },
    /// Activate a prepared system through the native controller
    Switch {
        /// Candidate name (store basename)
        candidate: String,
    },
    /// Check a prepared system through the native controller
    Check {
        /// Candidate name (store basename)
        candidate: String,
    },
    /// List prepared system generations
    #[command(visible_alias = "generations")]
    ListGenerations,
    /// Activate the retained previous generation
    Rollback,
    /// Restore the generation recorded before an interrupted activation
    Recover,
    /// Serve system-management requests to same-UID guest clients
    Serve,
    /// Run the persistent native guest service supervisor
    #[command(name = "__service-supervisor", hide = true)]
    ServiceSupervisor,
    /// Print whether serve would restart for a replaced APK (exit 0) or not
    /// (exit 1), from the apk-library marker and TERMUX_PKG_REDIRECT_SO
    #[command(name = "__apk-replaced", hide = true)]
    ApkReplaced,
    /// Continue a terminal's outer server after a re-exec into a newer nixpp
    #[command(name = "__outer-resume", hide = true)]
    OuterResume {
        #[arg(long)]
        listener_fd: i32,
        #[arg(long)]
        child: i32,
        #[arg(long)]
        dir: PathBuf,
    },
    /// Run COMMAND under a terminal's outer server without a terminal (tests)
    #[command(name = "__outer-supervise", hide = true)]
    OuterSupervise {
        #[arg(trailing_var_arg = true, allow_hyphen_values = true, required = true)]
        command: Vec<std::ffi::OsString>,
    },
    /// Run a controller operation directly, without the socket
    Controller {
        #[command(subcommand)]
        operation: Operation,
    },
    /// Set up a new runtime from a verified bootstrap
    Init(InitArgs),
    /// Build and activate the first managed guest from a native TermuxPP session
    Bootstrap {
        /// Flake URI, without an output fragment
        #[arg(long)]
        flake: String,
        /// Host name of the system configuration
        #[arg(long)]
        host: String,
        /// Guest account expected by the configuration
        #[arg(long)]
        user: String,
        /// Private directory containing the SSH identity and Nix configuration
        #[arg(long)]
        credentials: PathBuf,
    },
    /// Enter the guest or open the native TermuxPP shell
    #[command(visible_alias = "enter")]
    Login(LoginArgs),
    /// Open the native TermuxPP shell from an Android failsafe session
    NativeShell,
}

#[derive(Debug, Clone, Copy, clap::ValueEnum)]
pub enum FetchTarget {
    Latest,
}

#[derive(Debug, Args)]
pub struct LoginArgs {
    /// Use the outer Android/TermuxPP environment
    ///
    /// In SSH, allocate a terminal with ssh -t for an interactive native
    /// shell. Use termuxpp-adb-shell --outer for a direct native ADB session.
    #[arg(long, conflicts_with = "user")]
    outer: bool,

    /// Guest user name, used only when a new runtime is set up
    #[arg(long, env = "NIXPP_USER", default_value = bootstrap::DEFAULT_USERNAME)]
    user: String,

    /// Command and arguments after -- (default: an interactive shell)
    #[arg(
        trailing_var_arg = true,
        allow_hyphen_values = true,
        value_name = "ARG"
    )]
    args: Vec<std::ffi::OsString>,
}

#[derive(Debug, Subcommand)]
#[command(next_display_order = None)]
pub enum Operation {
    /// Check a candidate without activating or selecting it
    Check {
        candidate: String,
        /// Run the thorough runtime check
        #[arg(long)]
        thorough: bool,
    },
    /// Activate the matching Home Manager, then select the system
    Switch {
        candidate: String,
        /// Verified active Home Manager store path; first migration only
        #[arg(long, value_name = "PATH")]
        previous_home_manager: Option<String>,
    },
    /// Restore the generation recorded before an interrupted activation
    Recover,
    /// Activate and select the retained previous generation
    Rollback,
    /// List prepared system generations
    ListGenerations,
}

#[derive(Debug, Args)]
pub struct InitArgs {
    /// Bootstrap seed ZIP (default: bundled assets directory/bootstrap-aarch64.zip)
    #[arg(long, value_name = "FILE", conflicts_with = "resume")]
    bootstrap: Option<PathBuf>,

    /// Pinned package manifest
    #[arg(long, value_name = "FILE", conflicts_with = "resume")]
    manifest: Option<PathBuf>,

    /// Native CA certificate bundle
    #[arg(long, value_name = "FILE", conflicts_with = "resume")]
    certificate: Option<PathBuf>,

    /// Bundled launcher, seed and manifest directory (default: native prefix/share/nixpp)
    #[arg(long, value_name = "DIR", conflicts_with = "resume")]
    bootstrap_dir: Option<PathBuf>,

    /// Guest user name
    #[arg(long, default_value = bootstrap::DEFAULT_USERNAME, conflicts_with = "resume")]
    user: String,

    /// Continue an interrupted setup
    #[arg(long)]
    resume: bool,
}

/// How a command ends: an exit code and an optional message for stderr.
#[derive(Debug, PartialEq, Eq)]
pub struct Exit {
    code: u8,
    message: Option<String>,
}

impl Exit {
    fn success() -> Self {
        Self {
            code: 0,
            message: None,
        }
    }

    fn failure(message: impl Into<String>) -> Self {
        Self {
            code: 1,
            message: Some(message.into()),
        }
    }
}

/// Entry point of the binary.
pub fn run() -> ExitCode {
    let cli = Cli::parse();
    let ui = Ui::detect(cli.color, cli.json, cli.quiet);
    let exit = execute(&cli, &ui);
    if let Some(message) = &exit.message {
        ui.error(message);
    }
    ExitCode::from(exit.code)
}

fn non_empty(path: &Option<PathBuf>) -> Option<PathBuf> {
    path.clone().filter(|path| !path.as_os_str().is_empty())
}

fn execute(cli: &Cli, ui: &Ui) -> Exit {
    let runtime = non_empty(&cli.runtime);
    let socket = non_empty(&cli.socket);
    match &cli.command {
        Command::Completions { shell } => {
            let mut script = Vec::new();
            clap_complete::generate(*shell, &mut Cli::command(), "nixpp", &mut script);
            match io::stdout().lock().write_all(&script) {
                Ok(()) => Exit::success(),
                Err(error) => Exit::failure(format!("completions: {error}")),
            }
        }
        Command::Serve => native(serve_command(runtime, socket, ui)),
        Command::ServiceSupervisor => match native_runtime(runtime) {
            Ok(runtime) => match crate::services::run(&runtime) {
                Ok(()) => Exit::success(),
                Err(error) => Exit::failure(format!("service supervisor: {error:#}")),
            },
            Err(error) => Exit::failure(format!("service supervisor: {error:#}")),
        },
        Command::ApkReplaced => match native_runtime(runtime) {
            Ok(runtime) => {
                let replaced = crate::runtime_apk::replaced(&runtime);
                println!("{}", if replaced { "replaced" } else { "current" });
                Exit {
                    code: if replaced { 0 } else { 1 },
                    message: None,
                }
            }
            Err(error) => Exit::failure(format!("apk check: {error:#}")),
        },
        Command::OuterResume {
            listener_fd,
            child,
            dir,
        } => match crate::outer::resume(*listener_fd, *child, dir.clone()) {
            Ok(code) => Exit {
                code,
                message: None,
            },
            Err(error) => Exit::failure(format!("outer: {error:#}")),
        },
        Command::OuterSupervise { command } => {
            let mut guest = std::process::Command::new(&command[0]);
            guest.args(&command[1..]);
            match crate::outer::supervise(&mut guest) {
                Ok(code) => Exit {
                    code,
                    message: None,
                },
                Err(error) => Exit::failure(format!("outer: {error:#}")),
            }
        }
        Command::Controller { operation } => native(operate(runtime, operation, ui)),
        Command::Init(args) => {
            crate::progress::set_json(cli.json);
            init_command(runtime, args)
        }
        Command::Login(args) => login_command(runtime, args),
        Command::NativeShell => match crate::provision::enter_native_shell(&[]) {
            Ok(()) => Exit::success(),
            Err(error) => Exit::failure(format!("native-shell: {error:#}")),
        },
        Command::Bootstrap {
            flake,
            host,
            user,
            credentials,
        } => {
            match native_runtime(runtime)
                .and_then(|runtime| crate::enroll::enroll(&runtime, user, flake, host, credentials))
            {
                Ok(()) => Exit::success(),
                Err(error) => Exit::failure(format!("bootstrap: {error:#}")),
            }
        }
        command => {
            // Guest files are private to the user.
            // SAFETY: umask only changes the process file-creation mask.
            unsafe { libc::umask(0o077) };
            match guest_command(command, runtime, socket, ui) {
                Ok(()) => Exit::success(),
                Err(error) => Exit::failure(error.to_string()),
            }
        }
    }
}

fn require(value: Option<PathBuf>, message: &str) -> Result<PathBuf> {
    value.ok_or_else(|| Error::invalid(message))
}

fn report_stage(ui: &Ui, stage: Stage) {
    ui.step(match stage {
        Stage::Build => "building the system",
        Stage::Prepare => "preparing the candidate",
        Stage::Switch => "switching to the candidate",
    });
}

fn rebuild_system(
    ui: &Ui,
    runtime: Option<PathBuf>,
    socket: &Path,
    args: &BuildArgs,
) -> Result<()> {
    let runtime = require(runtime, "rebuild requires NIXPP_RUNTIME or --runtime")?;
    let generation = guest::rebuild(
        &runtime,
        socket,
        &args.flake,
        &args.host,
        args.rworker,
        &mut ProcessBuilder,
        &mut |stage| report_stage(ui, stage),
    )?;
    ui.ok("system switched");
    ui.print(&path_output(ui, &generation));
    Ok(())
}

const UPGRADE_CONFIG: &str = "/etc/nixpp/upgrade.json";

fn upgrade_system(
    ui: &Ui,
    runtime: Option<PathBuf>,
    socket: &Path,
    args: &UpgradeArgs,
) -> Result<()> {
    let target = guest::upgrade_target(
        Path::new(UPGRADE_CONFIG),
        args.flake.clone(),
        args.host.clone(),
    )?;
    if args.from_cache {
        let runtime = if args.dry_run {
            None
        } else {
            Some(require(
                runtime,
                "upgrade requires NIXPP_RUNTIME or --runtime",
            )?)
        };
        ui.step("verifying the cache pin");
        let generation = guest::cached_upgrade(&target, args.dry_run, &mut ProcessBuilder)?;
        if let Some(runtime) = runtime {
            guest::activate_system(&runtime, socket, &generation, &mut |stage| {
                report_stage(ui, stage);
            })?;
            ui.ok("system switched");
        }
        ui.print(&path_output(ui, &generation));
    } else if args.dry_run {
        guest::plan_upgrade(&target, &mut ProcessBuilder)?;
    } else {
        let runtime = require(runtime, "upgrade requires NIXPP_RUNTIME or --runtime")?;
        report_stage(ui, Stage::Build);
        let generation = guest::build_upgrade(&target, args.rworker, &mut ProcessBuilder)?;
        guest::activate_system(&runtime, socket, &generation, &mut |stage| {
            report_stage(ui, stage);
        })?;
        ui.ok("system switched");
        ui.print(&path_output(ui, &generation));
    }
    Ok(())
}

fn doctor(ui: &Ui, socket: &Path) -> Result<()> {
    let mut builder = ProcessBuilder;
    let controller = guest::manage(socket, "list-generations", None).map(|_| ());
    let store = guest::probe_store(&mut builder, None);
    let builders = guest::probe_builders(&mut builder);
    let cache = guest::upgrade_target(Path::new(UPGRADE_CONFIG), None, None)
        .and_then(|target| guest::cached_upgrade(&target, true, &mut builder))
        .map(|_| ());
    let checks = [
        ("native controller", controller),
        ("local Nix store", store),
        ("remote builders", builders),
        ("signed cache pin", cache),
    ];
    let mut results = serde_json::Map::new();
    let mut ok = true;
    for (name, result) in checks {
        if let Err(error) = result {
            ok = false;
            results.insert(
                name.to_owned(),
                json!({ "ok": false, "error": error.to_string() }),
            );
            if !ui.json() {
                ui.warn(&format!("{name}: {error}"));
            }
        } else {
            results.insert(name.to_owned(), json!({ "ok": true }));
            if !ui.json() {
                ui.ok(name);
            }
        }
    }
    if ui.json() {
        ui.print(&canonical_json(&json!({ "ok": ok, "checks": results })));
    }
    if !ok {
        return Err(Error::invalid("one or more checks failed"));
    }
    Ok(())
}

fn guest_command(
    command: &Command,
    runtime: Option<PathBuf>,
    socket: Option<PathBuf>,
    ui: &Ui,
) -> Result<()> {
    let socket = socket.unwrap_or_else(|| PathBuf::from(DEFAULT_SOCKET));
    match command {
        Command::Prepare { generation } => {
            let runtime = require(runtime, "prepare requires --runtime or NIXPP_RUNTIME")?;
            let candidate = guest::prepare(&runtime, generation)?;
            ui.print(&path_output(ui, &candidate));
        }
        Command::Build(args) => {
            ui.step(&format!("building {} remotely", args.host));
            let generation =
                guest::build_system(&args.flake, &args.host, args.rworker, &mut ProcessBuilder)?;
            ui.print(&path_output(ui, &generation));
        }
        Command::Upgrade(args) => upgrade_system(ui, runtime, &socket, args)?,
        Command::Fetch {
            target: FetchTarget::Latest,
        } => upgrade_system(ui, runtime, &socket, &UpgradeArgs::default())?,
        Command::Doctor => doctor(ui, &socket)?,
        Command::Diff { from, to } => {
            let runtime = require(runtime, "diff requires NIXPP_RUNTIME or --runtime")?;
            let format = if ui.json() {
                guest::DiffFormat::Nix
            } else {
                guest::DiffFormat::Dix {
                    color: ui.stdout_color(),
                }
            };
            let (from, to, diff) = guest::diff_generations(
                &runtime,
                from.as_deref(),
                to.as_deref(),
                format,
                &mut ProcessBuilder,
            )?;
            if ui.json() {
                ui.print(&canonical_json(
                    &json!({ "from": from, "to": to, "diff": diff }),
                ));
            } else if diff.trim().is_empty() {
                ui.print("No closure differences.");
            } else {
                ui.print(diff.trim_end());
            }
        }
        Command::Gc {
            keep_generations,
            dry_run,
        } => {
            let runtime = require(runtime, "gc requires NIXPP_RUNTIME or --runtime")?;
            let report = crate::gc::run(&runtime, usize::from(*keep_generations), *dry_run)?;
            if ui.json() {
                ui.print(&canonical_json(&serde_json::to_value(report)?));
            } else if let Some(reason) = report.deferred {
                ui.print(&format!("GC deferred: {reason}"));
            } else if report.prune.is_empty() {
                ui.print("No system generations to prune.");
            } else {
                let action = if *dry_run { "Would prune" } else { "Pruned" };
                for name in report.prune {
                    ui.print(&format!("{action} {name}"));
                }
            }
        }
        Command::CachePinObsolete { generation } => {
            let runtime = require(
                runtime,
                "cache pin check requires NIXPP_RUNTIME or --runtime",
            )?;
            ui.print(&crate::gc::pin_is_obsolete(&runtime, generation)?.to_string());
        }
        Command::Rebuild(args) => rebuild_system(ui, runtime, &socket, args)?,
        Command::Switch { candidate } => {
            let response = guest::manage(&socket, "switch", Some(candidate))?;
            ui.ok(&format!("switched to {candidate}"));
            print_response(ui, &response);
        }
        Command::Check { candidate } => {
            let response = guest::manage(&socket, "check", Some(candidate))?;
            ui.ok(&format!("{candidate} passed the runtime check"));
            print_response(ui, &response);
        }
        Command::Rollback => {
            let response = guest::manage(&socket, "rollback", None)?;
            ui.ok("rolled back to the previous generation");
            print_response(ui, &response);
        }
        Command::Recover => {
            let response = guest::manage(&socket, "recover", None)?;
            ui.ok("interrupted activation recovered");
            print_response(ui, &response);
        }
        Command::ListGenerations | Command::Status { .. } => {
            let response = guest::manage(&socket, "list-generations", None)?;
            let list = guest::generations(&response)?;
            let list = match runtime.as_deref() {
                // An already-running native controller may predate the columns.
                Some(runtime) if list.iter().any(|item| item.number.is_none()) => {
                    controller::annotate_generations(runtime, list)?
                }
                _ => list,
            };
            let mut list = list;
            if matches!(command, Command::Status { all: false }) {
                list.retain(|generation| generation.current || generation.previous);
            }
            let list = serde_json::to_value(list)?;
            let table = !ui.json() && Ui::stdout_is_terminal();
            ui.print(&render_generations(ui, &list, table)?);
        }
        Command::Completions { .. }
        | Command::Serve
        | Command::Controller { .. }
        | Command::Init(_)
        | Command::Login(_)
        | Command::NativeShell
        | Command::ServiceSupervisor
        | Command::ApkReplaced
        | Command::OuterResume { .. }
        | Command::OuterSupervise { .. }
        | Command::Bootstrap { .. } => {
            unreachable!("handled before the guest commands")
        }
    }
    Ok(())
}

/// A path as plain text, or `{"path": ...}` with `--json`.
fn path_output(ui: &Ui, path: &Path) -> String {
    if ui.json() {
        canonical_json(&json!({ "path": path.to_string_lossy() }))
    } else {
        path.display().to_string()
    }
}

/// Only machine-readable mode echoes the controller response.
fn print_response(ui: &Ui, response: &Value) {
    if ui.json() {
        ui.print(&canonical_json(response));
    }
}

/// The generation list: a table for people, sorted-key JSON otherwise.
fn render_generations(ui: &Ui, list: &Value, table: bool) -> Result<String> {
    if !table {
        return Ok(canonical_json(list));
    }
    let generations: Vec<controller::Generation> = serde_json::from_value(list.clone())
        .map_err(|_| Error::invalid("invalid native controller response"))?;
    Ok(generations_table(ui, &generations))
}

fn generations_table(ui: &Ui, generations: &[controller::Generation]) -> String {
    let rows: Vec<Vec<String>> = generations
        .iter()
        .map(|generation| {
            let mut state = Vec::new();
            if generation.current {
                state.push("current");
            }
            if generation.previous {
                state.push("previous");
            }
            vec![
                generation
                    .number
                    .map_or_else(|| "-".into(), |n| n.to_string()),
                generation.date.as_deref().unwrap_or("-").into(),
                generation.generation.clone(),
                generation.home_manager.clone(),
                state.join(", "),
            ]
        })
        .collect();
    ui.table(
        &["GEN", "DATE (UTC)", "SYSTEM", "HOME MANAGER", "STATE"],
        &rows,
        &|column, text| match (column, text) {
            (4, text) if text.starts_with("current") => Some(Style::Green),
            (4, "previous") => Some(Style::Yellow),
            _ => None,
        },
    )
}

/// The directory of the running executable, the default native runtime.
fn executable_directory() -> Result<PathBuf> {
    let executable = crate::provision::running_executable()
        .map_err(|error| Error::invalid(format!("locate nixpp: {error}")))?;
    executable
        .parent()
        .map(Path::to_path_buf)
        .ok_or_else(|| Error::invalid("cannot determine the runtime directory"))
}

fn serve_command(runtime: Option<PathBuf>, socket: Option<PathBuf>, ui: &Ui) -> Result<u8> {
    let socket = require(socket, "serve requires --socket or NIXPP_SOCKET")?;
    let runtime = match runtime {
        Some(runtime) => runtime,
        None => executable_directory()?,
    };
    match server::serve(&runtime, &socket, &mut SessionRunner::new())? {
        Served::ReloadApk => crate::runtime_apk::restart(&runtime, &[]).map(|()| 0),
        Served::AlreadyRunning => {
            ui.warn("a native controller already serves this runtime");
            Ok(0)
        }
    }
}

fn operate(runtime: Option<PathBuf>, operation: &Operation, ui: &Ui) -> Result<u8> {
    let runtime = match runtime {
        Some(runtime) => runtime,
        None => executable_directory()?,
    };
    let mut runner = SessionRunner::new();
    let status = match operation {
        Operation::Check {
            candidate,
            thorough,
        } => controller::check(&runtime, candidate, *thorough, &mut runner)?,
        Operation::Switch {
            candidate,
            previous_home_manager,
        } => controller::switch(
            &runtime,
            candidate,
            previous_home_manager.as_deref(),
            &mut runner,
            None,
        )?,
        Operation::Recover => controller::recover(&runtime, &mut runner)?,
        Operation::Rollback => controller::rollback(&runtime, &mut runner)?,
        Operation::ListGenerations => {
            let list = serde_json::to_value(controller::generations(&runtime)?)?;
            let table = !ui.json() && Ui::stdout_is_terminal();
            ui.print(&render_generations(ui, &list, table)?);
            0
        }
    };
    Ok(controller::exit_code(status))
}

/// Map a native controller outcome to the historical exit codes and texts.
fn native(result: Result<u8>) -> Exit {
    match result {
        Ok(code) => Exit {
            code,
            message: None,
        },
        Err(error) => native_failure(&error),
    }
}

fn native_failure(error: &Error) -> Exit {
    let (code, message) = match error {
        Error::Timeout { .. } => (
            124,
            "System candidate check exceeded its execution budget.".to_owned(),
        ),
        Error::Interrupted => (130, "System candidate check interrupted.".to_owned()),
        Error::Terminated => (143, "System candidate check terminated.".to_owned()),
        other => (1, format!("Cannot manage system candidate: {other}")),
    };
    Exit {
        code,
        message: Some(message),
    }
}

/// `--runtime`/`NIXPP_RUNTIME`, else the default below `HOME`.
fn native_runtime(runtime: Option<PathBuf>) -> anyhow::Result<PathBuf> {
    match runtime {
        Some(runtime) => Ok(runtime),
        None => std::env::var_os("HOME")
            .context("requires HOME or --runtime")
            .and_then(|home| crate::provision::default_runtime(Path::new(&home))),
    }
}

/// Enter the guest; when that fails, explain and continue in the native
/// shell instead of ending the terminal session.
fn login_command(runtime: Option<PathBuf>, args: &LoginArgs) -> Exit {
    if args.outer {
        if !cfg!(target_os = "android") {
            return match crate::outer::request(&args.args) {
                Ok(code) => Exit {
                    code,
                    message: None,
                },
                Err(error) => Exit::failure(format!("enter --outer: {error:#}")),
            };
        }
        return match crate::provision::enter_native_shell(&args.args) {
            Ok(()) => Exit::success(),
            Err(error) => Exit::failure(format!("enter --outer: {error:#}")),
        };
    }
    if !cfg!(target_os = "android") {
        return match crate::provision::enter_current_guest(&args.args) {
            Ok(()) => Exit::success(),
            Err(error) => Exit::failure(format!("enter: {error:#}")),
        };
    }
    let error = match native_runtime(runtime) {
        Ok(runtime) => match crate::provision::login(&runtime, &args.user, &args.args) {
            Ok(code) => {
                return Exit {
                    code,
                    message: None,
                };
            }
            Err(error) => error,
        },
        Err(error) => error,
    };
    if !args.args.is_empty() {
        return Exit::failure(format!("cannot start guest command: {error:#}"));
    }
    eprintln!("nixpp: cannot enter the Nix guest: {error:#}");
    eprintln!("Starting the native shell instead; run `nixpp enter` to retry.");
    match crate::provision::native_shell() {
        Ok(()) => Exit::success(),
        Err(error) => Exit::failure(format!("{error:#}")),
    }
}

fn init_command(runtime: Option<PathBuf>, args: &InitArgs) -> Exit {
    let runtime = match native_runtime(runtime) {
        Ok(runtime) => runtime,
        Err(error) => return Exit::failure(format!("init {error:#}")),
    };
    let result = if args.resume {
        bootstrap::resume(&runtime)
    } else {
        crate::provision::init(
            &runtime,
            crate::provision::Inputs {
                seed: args.bootstrap.as_deref(),
                manifest: args.manifest.as_deref(),
                certificate: args.certificate.as_deref(),
                bootstrap_dir: args.bootstrap_dir.as_deref(),
                user: &args.user,
            },
        )
    };
    match result {
        Ok(()) => Exit::success(),
        Err(error) => Exit::failure(format!("{error:#}")),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use clap::CommandFactory;

    fn parse(arguments: &[&str]) -> std::result::Result<Cli, clap::Error> {
        Cli::try_parse_from(std::iter::once("nixpp").chain(arguments.iter().copied()))
    }

    #[test]
    fn command_definition_is_consistent() {
        Cli::command().debug_assert();
    }

    #[test]
    fn help_lists_the_documented_commands_alphabetically() {
        let help = Cli::command().render_help().to_string();
        let commands: Vec<_> = help
            .split_once("Commands:\n")
            .unwrap()
            .1
            .lines()
            .map_while(|line| line.split_whitespace().next())
            .collect();
        assert_eq!(
            commands,
            [
                "bootstrap",
                "build",
                "check",
                "completions",
                "controller",
                "diff",
                "doctor",
                "fetch",
                "gc",
                "help",
                "init",
                "list-generations",
                "login",
                "native-shell",
                "prepare",
                "rebuild",
                "recover",
                "rollback",
                "serve",
                "status",
                "switch",
                "upgrade",
            ]
        );
    }

    #[test]
    fn launcher_syntax_parses() {
        let cli = parse(&["--runtime", "/rt", "serve", "--socket", "/rt/nixpp.sock"]).unwrap();
        assert_eq!(cli.runtime, Some(PathBuf::from("/rt")));
        assert_eq!(cli.socket, Some(PathBuf::from("/rt/nixpp.sock")));
        assert!(matches!(cli.command, Command::Serve));
    }

    #[test]
    fn diff_accepts_zero_or_two_generation_selectors() {
        assert!(parse(&["diff"]).is_ok());
        assert!(parse(&["diff", "2", "5"]).is_ok());
        assert!(parse(&["diff", "2"]).is_err());
    }

    #[test]
    fn native_controller_syntax_parses() {
        let cli = parse(&[
            "--runtime",
            "/rt",
            "controller",
            "check",
            "cand",
            "--thorough",
        ])
        .unwrap();
        assert!(matches!(
            cli.command,
            Command::Controller {
                operation: Operation::Check { thorough: true, .. }
            }
        ));
        let cli = parse(&[
            "--runtime",
            "/rt",
            "controller",
            "switch",
            "cand",
            "--previous-home-manager",
            "/nix/store/x",
        ])
        .unwrap();
        let Command::Controller {
            operation:
                Operation::Switch {
                    previous_home_manager,
                    ..
                },
        } = cli.command
        else {
            panic!("not a switch");
        };
        assert_eq!(previous_home_manager.as_deref(), Some("/nix/store/x"));
        for operation in ["recover", "rollback", "list-generations"] {
            parse(&["--runtime", "/rt", "controller", operation]).unwrap();
        }
    }

    #[test]
    fn global_options_work_after_the_subcommand() {
        let cli = parse(&["prepare", "--runtime", "/rt", "/nix/store/g"]).unwrap();
        assert_eq!(cli.runtime, Some(PathBuf::from("/rt")));
        let cli = parse(&["--json", "-q", "--color", "never", "list-generations"]).unwrap();
        assert!(cli.json && cli.quiet);
        assert_eq!(cli.color, ColorChoice::Never);
    }

    #[test]
    fn build_requires_flake_and_host() {
        assert!(parse(&["build", "--flake", "x"]).is_err());
        assert!(parse(&["build", "--host", "h"]).is_err());
        assert!(parse(&["rebuild", "--flake", "x", "--host", "h", "--rworker"]).is_ok());
    }

    #[test]
    fn init_arguments() {
        assert!(parse(&["init"]).is_ok());
        assert!(matches!(
            parse(&["init", "--resume"]).unwrap().command,
            Command::Init(_)
        ));
        assert!(
            parse(&[
                "init",
                "--bootstrap",
                "a",
                "--manifest",
                "m",
                "--certificate",
                "c"
            ])
            .is_ok()
        );
        assert!(parse(&["init", "--bootstrap", "a"]).is_ok());
        assert!(parse(&["init", "--resume", "--bootstrap", "a"]).is_err());
    }

    #[test]
    fn unknown_commands_are_rejected() {
        assert!(parse(&["frobnicate"]).is_err());
        assert!(parse(&["--color", "sometimes", "recover"]).is_err());
    }

    #[test]
    fn empty_paths_count_as_unset() {
        assert_eq!(non_empty(&Some(PathBuf::new())), None);
        assert_eq!(non_empty(&None), None);
        assert_eq!(
            non_empty(&Some(PathBuf::from("/x"))),
            Some(PathBuf::from("/x"))
        );
    }

    #[test]
    fn native_failures_keep_the_historical_exit_codes() {
        let cases = [
            (
                Error::invalid("nope"),
                1,
                "Cannot manage system candidate: nope",
            ),
            (
                Error::Timeout { seconds: 3 },
                124,
                "System candidate check exceeded its execution budget.",
            ),
            (
                Error::Interrupted,
                130,
                "System candidate check interrupted.",
            ),
            (Error::Terminated, 143, "System candidate check terminated."),
        ];
        for (error, code, message) in cases {
            let exit = native_failure(&error);
            assert_eq!(exit.code, code);
            assert_eq!(exit.message.as_deref(), Some(message));
        }
        assert_eq!(
            native(Ok(7)),
            Exit {
                code: 7,
                message: None
            }
        );
    }

    #[test]
    fn signal_statuses_map_to_shell_exit_codes() {
        assert_eq!(controller::exit_code(0), 0);
        assert_eq!(controller::exit_code(3), 3);
        assert_eq!(controller::exit_code(-15), 143);
        assert_eq!(controller::exit_code(-2), 130);
    }

    #[test]
    fn generation_list_is_sorted_key_json_when_not_a_table() {
        let ui = Ui::new(false, false, false, false);
        let list =
            json!([{"generation": "g", "homeManager": "h", "current": true, "previous": false}]);
        assert_eq!(
            render_generations(&ui, &list, false).unwrap(),
            r#"[{"current": true, "generation": "g", "homeManager": "h", "previous": false}]"#
        );
        assert_eq!(render_generations(&ui, &json!([]), false).unwrap(), "[]");
    }

    #[test]
    fn generation_table_lists_states() {
        let ui = Ui::new(false, false, false, false);
        let list = json!([
            {"number": 1, "date": "2026-11-18 14:00:00Z", "generation": "g1", "homeManager": "h1", "current": true, "previous": false},
            {"generation": "g2", "homeManager": "h2", "current": false, "previous": true},
            {"generation": "g3", "homeManager": "h3", "current": false, "previous": false},
        ]);
        let table = render_generations(&ui, &list, true).unwrap();
        let lines: Vec<&str> = table.lines().collect();
        assert_eq!(
            lines[0],
            "GEN  DATE (UTC)            SYSTEM  HOME MANAGER  STATE"
        );
        assert_eq!(
            lines[1],
            "1    2026-11-18 14:00:00Z  g1      h1            current"
        );
        assert_eq!(
            lines[2],
            "-    -                     g2      h2            previous"
        );
        assert_eq!(lines[3], "-    -                     g3      h3");
        assert!(render_generations(&ui, &json!("nope"), true).is_err());
    }

    #[test]
    fn json_outputs() {
        let json_ui = Ui::new(false, false, false, true);
        let plain = Ui::new(false, false, false, false);
        assert_eq!(path_output(&json_ui, Path::new("/x")), r#"{"path": "/x"}"#);
        assert_eq!(path_output(&plain, Path::new("/x")), "/x");
    }

    #[test]
    fn guest_commands_need_their_runtime() {
        let ui = Ui::new(false, false, true, false);
        let prepare = Command::Prepare {
            generation: PathBuf::from("/nix/store/x"),
        };
        let error = guest_command(&prepare, None, None, &ui).unwrap_err();
        assert_eq!(
            error.to_string(),
            "prepare requires --runtime or NIXPP_RUNTIME"
        );
        let rebuild = Command::Rebuild(BuildArgs {
            flake: "source".to_owned(),
            host: "host".to_owned(),
            rworker: false,
        });
        let error = guest_command(&rebuild, None, None, &ui).unwrap_err();
        assert_eq!(
            error.to_string(),
            "rebuild requires NIXPP_RUNTIME or --runtime"
        );
    }

    #[test]
    fn invalid_candidates_fail_before_any_socket_access() {
        let ui = Ui::new(false, false, true, false);
        for candidate in ["../escape", "/absolute", "short"] {
            let command = Command::Switch {
                candidate: candidate.to_owned(),
            };
            let error = guest_command(
                &command,
                None,
                Some(PathBuf::from("/nonexistent/sock")),
                &ui,
            )
            .unwrap_err();
            assert_eq!(error.to_string(), "invalid system candidate name");
        }
    }

    #[test]
    fn serve_requires_a_socket() {
        let ui = Ui::new(false, false, true, false);
        let error = serve_command(Some(PathBuf::from("/rt")), None, &ui).unwrap_err();
        assert_eq!(error.to_string(), "serve requires --socket or NIXPP_SOCKET");
    }

    #[test]
    fn login_has_an_enter_alias_and_passes_shell_arguments() {
        for name in ["login", "enter"] {
            let Command::Login(args) = parse(&[name, "--user", "guest", "-c", "true"])
                .unwrap()
                .command
            else {
                panic!("not login");
            };
            assert_eq!(args.user, "guest");
            assert_eq!(args.args, ["-c", "true"]);
        }
        let Command::Login(args) = parse(&["enter"]).unwrap().command else {
            panic!("not login");
        };
        assert!(args.args.is_empty());
        let Command::Login(args) = parse(&["enter", "--outer", "--", "ls", "-al", "two words"])
            .unwrap()
            .command
        else {
            panic!("not login");
        };
        assert!(args.outer);
        assert_eq!(args.args, ["ls", "-al", "two words"]);
    }

    #[test]
    fn init_bootstrap_directory_is_not_a_resume_input() {
        assert!(parse(&["init", "--bootstrap-dir", "/seed"]).is_ok());
        assert!(parse(&["init", "--resume", "--bootstrap-dir", "/seed"]).is_err());
    }
}
