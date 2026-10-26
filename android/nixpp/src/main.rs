use anyhow::Result;
use clap::{Parser, Subcommand};
use std::path::PathBuf;

#[derive(Debug, Parser)]
#[command(
    name = "nixpp",
    version,
    about = "Fetch and activate reference-free Nix outputs on Termux",
    long_about = "A small Termux-side client. Nix evaluates and builds outputs on a trusted Linux host; nixpp verifies and installs them on the phone."
)]
struct Cli {
    #[command(subcommand)]
    command: Command,
}

#[derive(Debug, Subcommand)]
enum Command {
    /// Fetch one reference-free output from a signed Nix binary cache.
    Fetch {
        /// Nix binary cache URL.
        #[arg(long)]
        cache: Option<String>,
        /// Full path of the output in the Nix store.
        #[arg(long)]
        store_path: String,
        /// New directory to create from this output.
        #[arg(long)]
        destination: PathBuf,
        /// Trusted cache key in NAME:BASE64 format.
        #[arg(long, env = "NIXPP_PUBLIC_KEY")]
        public_key: Option<String>,
        /// Private netrc file for authenticated caches (mode 0600 or stricter).
        #[arg(long)]
        netrc_file: Option<PathBuf>,
    },
    /// Build a Termux bundle on a Nix host, verify it, and activate it.
    Switch {
        /// Flake installable that produces a Termux bundle.
        #[arg(long)]
        flake: Option<String>,
        /// SSH host with Nix and a signing key configured.
        #[arg(long, env = "NIXPP_BUILDER")]
        builder: Option<String>,
        /// Trusted cache key in NAME:BASE64 format.
        #[arg(long, env = "NIXPP_PUBLIC_KEY")]
        public_key: Option<String>,
    },
    /// Show the active generation and installed generation IDs.
    Status {
        /// Show every retained generation.
        #[arg(long)]
        all: bool,
        /// Print machine-readable JSON.
        #[arg(long)]
        json: bool,
    },
    /// List installed generations that can be used for rollback.
    Generations,
    /// Roll back to a generation number or full SHA-256 ID.
    Rollback {
        /// Generation number shown by `nixpp status` or `nixpp generations`.
        generation: String,
    },
    /// Remove old generations and Termux APT packages no retained generation needs.
    Gc {
        /// Number of newest generations to retain, plus the active generation.
        #[arg(long, default_value_t = 3)]
        keep: usize,
        /// Show what would be removed without changing generations or packages.
        #[arg(long)]
        dry_run: bool,
    },
}

fn main() {
    if let Err(error) = run(Cli::parse()) {
        eprintln!("nixpp: {error:#}");
        std::process::exit(1);
    }
}

fn run(cli: Cli) -> Result<()> {
    match cli.command {
        Command::Fetch {
            cache,
            store_path,
            destination,
            public_key,
            netrc_file,
        } => nixpp::fetch(
            cache.as_deref(),
            &store_path,
            &destination,
            public_key.as_deref(),
            netrc_file.as_deref(),
        ),
        Command::Switch {
            flake,
            builder,
            public_key,
        } => nixpp::switch_profile(flake.as_deref(), builder.as_deref(), public_key.as_deref()),
        Command::Status { all, json } => nixpp::status(all, json),
        Command::Generations => nixpp::generations(),
        Command::Rollback { generation } => nixpp::rollback(&generation),
        Command::Gc { keep, dry_run } => nixpp::gc(keep, dry_run),
    }
}
