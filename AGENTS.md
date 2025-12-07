# Repository Guidelines

## Environment preparation
- Before invoking the `nix` CLI inside this repository, run `source /etc/profile.d/nix.sh` **only when working in the cloud environment**. Do not source it when running from the Codex CLI or GitHub Copilot context.
- After sourcing (cloud only), verify the installation with `nix --version` if needed.

## Deployment
- Do not *EVER* commit or push changes from this environment.
- To deploy changes to a host, run `~/bin/zhj nixos::rebuild --target-host TARGET_HOST`.

## Code Style
- Nix code changes should be formatted correctly with `nixfmt-rfc-style`.
- `statix` checks should pass.
- Tofu code changes should be formatted with `tofu fmt`.
