# Repository Guidelines

## Environment preparation
- Before invoking the `nix` CLI inside this repository, run `source /etc/profile.d/nix.sh` to make the command available in the container environment.
- After sourcing, verify the installation with `nix --version` if needed.

## Deployment
- Do not *EVER* commit or push changes from this environment.
- To deploy changes to a host, run `~/bin/zhj nixos::rebuild --target-host TARGET_HOST`.
