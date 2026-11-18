use anyhow::{Context, Result};
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
    /// Inspect configured outputs pinned in the binary cache.
    Cache {
        #[command(subcommand)]
        command: CacheCommand,
    },
    /// Compare changes recorded between two installed generations.
    Diff {
        /// Older generation number or full SHA-256 ID (defaults to the latest non-current generation).
        old: Option<String>,
        /// Newer generation number or full SHA-256 ID (defaults to the current generation).
        new: Option<String>,
    },
    /// Check the nixpp configuration, S3 cache, credentials, and builder.
    Doctor,
    /// Fetch one reference-free output from a signed Nix binary cache.
    Fetch {
        /// Fetch the configured latest profile (the same operation as `upgrade`).
        target: Option<String>,
        /// Nix binary cache URL.
        #[arg(long)]
        cache: Option<String>,
        /// Full path of the output in the Nix store.
        #[arg(long)]
        store_path: Option<String>,
        /// New directory to create from this output.
        #[arg(long)]
        destination: Option<PathBuf>,
        /// Trusted cache key in NAME:BASE64 format.
        #[arg(long, env = "NIXPP_PUBLIC_KEY")]
        public_key: Option<String>,
        /// Private netrc file for authenticated caches (mode 0600 or stricter).
        #[arg(long)]
        netrc_file: Option<PathBuf>,
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
    /// List installed generations that can be used for rollback.
    Generations,
    /// Pin an installed generation so garbage collection keeps it.
    Pin {
        /// Generation number or full SHA-256 ID.
        generation: String,
    },
    /// Roll back to a generation number or full SHA-256 ID.
    Rollback {
        /// Generation number shown by `nixpp status` or `nixpp generations`.
        generation: String,
    },
    /// Remove a generation pin.
    Unpin {
        /// Generation number or full SHA-256 ID.
        generation: String,
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
    /// Upgrade to the configured default Termux profile.
    Upgrade {
        /// Install the cache pin selected by `cache_profile` instead of building:
        /// needs no SSH and no builder, only read access to the S3 cache.
        #[arg(long)]
        from_cache: bool,
        /// Compare the configured profile without activating it.
        #[arg(long)]
        dry_run: bool,
    },
}

#[derive(Debug, Subcommand)]
enum CacheCommand {
    /// List configured Niks3 pins and their store paths.
    List {
        /// Print machine-readable JSON.
        #[arg(long)]
        json: bool,
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
            target,
            cache,
            store_path,
            destination,
            public_key,
            netrc_file,
        } => {
            if target.as_deref() == Some("latest") {
                anyhow::ensure!(
                    cache.is_none()
                        && store_path.is_none()
                        && destination.is_none()
                        && public_key.is_none()
                        && netrc_file.is_none(),
                    "`fetch latest` uses the configured upgrade settings; do not pass fetch overrides"
                );
                nixpp::upgrade_profile(false)
            } else {
                anyhow::ensure!(target.is_none(), "unknown fetch target; use `latest`");
                nixpp::fetch(
                    cache.as_deref(),
                    store_path
                        .as_deref()
                        .context("--store-path is required unless fetching `latest`")?,
                    destination
                        .as_deref()
                        .context("--destination is required unless fetching `latest`")?,
                    public_key.as_deref(),
                    netrc_file.as_deref(),
                )
            }
        }
        Command::Cache { command } => match command {
            CacheCommand::List { json } => nixpp::cache_list(json),
        },
        Command::Switch {
            flake,
            builder,
            public_key,
        } => nixpp::switch_profile(flake.as_deref(), builder.as_deref(), public_key.as_deref()),
        Command::Upgrade {
            from_cache,
            dry_run,
        } => {
            if from_cache {
                nixpp::upgrade_from_cache(dry_run)
            } else {
                nixpp::upgrade_profile(dry_run)
            }
        }
        Command::Doctor => nixpp::doctor(),
        Command::Diff { old, new } => nixpp::diff(old.as_deref(), new.as_deref()),
        Command::Status { all, json } => nixpp::status(all, json),
        Command::Generations => nixpp::generations(),
        Command::Pin { generation } => nixpp::pin(&generation, true),
        Command::Rollback { generation } => nixpp::rollback(&generation),
        Command::Unpin { generation } => nixpp::pin(&generation, false),
        Command::Gc { keep, dry_run } => nixpp::gc(keep, dry_run),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use clap::Parser;

    fn upgrade_flags(arguments: &[&str]) -> (bool, bool) {
        match Cli::try_parse_from(arguments).unwrap().command {
            Command::Upgrade {
                from_cache,
                dry_run,
            } => (from_cache, dry_run),
            other => panic!("expected upgrade, got {other:?}"),
        }
    }

    #[test]
    fn plain_upgrade_keeps_the_builder_path() {
        assert_eq!(upgrade_flags(&["nixpp", "upgrade"]), (false, false));
        assert_eq!(
            upgrade_flags(&["nixpp", "upgrade", "--dry-run"]),
            (false, true)
        );
    }

    #[test]
    fn upgrade_from_cache_accepts_dry_run_in_any_order() {
        assert_eq!(
            upgrade_flags(&["nixpp", "upgrade", "--from-cache"]),
            (true, false)
        );
        assert_eq!(
            upgrade_flags(&["nixpp", "upgrade", "--from-cache", "--dry-run"]),
            (true, true)
        );
        assert_eq!(
            upgrade_flags(&["nixpp", "upgrade", "--dry-run", "--from-cache"]),
            (true, true)
        );
    }

    #[test]
    fn upgrade_rejects_builder_and_cache_overrides() {
        for argument in ["--builder", "--flake", "--public-key", "--cache"] {
            assert!(
                Cli::try_parse_from(["nixpp", "upgrade", "--from-cache", argument, "x"]).is_err(),
                "{argument} must not be accepted by upgrade"
            );
        }
    }

    #[test]
    fn from_cache_is_only_an_upgrade_flag() {
        assert!(Cli::try_parse_from(["nixpp", "switch", "--from-cache"]).is_err());
        assert!(Cli::try_parse_from(["nixpp", "fetch", "latest", "--from-cache"]).is_err());
    }
}
