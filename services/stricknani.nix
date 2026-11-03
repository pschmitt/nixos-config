# Stricknani production (wool/stricken/wolle on rofl-10): stage selector.
#
# ONE constant below picks what runs. Everything else is derived from it:
#
#   stage                  backend  edge maintenance  use
#   ---------------------  -------  ----------------  ----------------------------
#   "rust"                 Rust     off               cutover end state (default)
#   "rust-maintenance"     Rust     on                window step: Rust on imported data
#   "python-maintenance"   Python   on                window step: close the edge first
#   "python"               Python   off               pre-cutover production / rollback
#
# Cutover window (details: docs/rust-migration-plan.md and
# docs/production-cutover-checklist.md in the stricknani repo):
#   0. monit unmonitor stricknani          (on rofl-10)
#   1. stage = "python-maintenance"; deploy   -> edge answers 503, Python still up
#      wait for in-flight requests to drain
#   2. systemctl stop stricknani; take the matched DB+media snapshot; run
#      `stricknani-server import-snapshot ... --destination /var/lib/stricknani-rust`
#      (root; stricknani-server is in PATH in every stage); chown -R stricknani:stricknani
#   3. stage = "rust-maintenance"; deploy     -> Rust serves the imported data, edge still 503
#      verify (health, login, OIDC, media, two-owner check; use
#      stricknani.maintenance.bypassAddresses for an operator address if needed)
#   4. stage = "rust"; deploy                 -> barrier lifted
#      final public checks; monit monitor stricknani
#
# Rollback (only before the Rust service has accepted writes; /var/lib/stricknani
# is never modified by the Rust service):
#   keep/raise the barrier: stage = "python-maintenance"; deploy; verify Python
#   health + login; then stage = "python"; deploy. The Python input is pinned to
#   tag v0.1.0 (`stricknani-python` in flake.nix). After Rust accepted writes do
#   NOT switch back blindly: follow the "After Rust accepts writes" runbook.
{ inputs, pkgs, ... }:
let
  stage = "rust";

  stages = {
    rust = {
      module = ./stricknani-rust.nix;
      maintenance = false;
    };
    rust-maintenance = {
      module = ./stricknani-rust.nix;
      maintenance = true;
    };
    python-maintenance = {
      module = ./stricknani-python.nix;
      maintenance = true;
    };
    python = {
      module = ./stricknani-python.nix;
      maintenance = false;
    };
  };
  selected = stages.${stage};
in
{
  imports = [
    selected.module
    ./stricknani-maintenance.nix
  ];

  stricknani.maintenance.enable = selected.maintenance;

  # The Rust server binary (importer, account CLI) is available in every stage,
  # including "python-maintenance", so the snapshot import can run before the
  # service is switched over.
  environment.systemPackages = [
    inputs.stricknani.packages.${pkgs.stdenv.hostPlatform.system}.stricknani-rust
  ];
}
