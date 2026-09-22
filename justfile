set shell := ["bash", "-euo", "pipefail", "-c"]
set positional-arguments

# Recipe bodies are kept thin and live as scripts under just/*.sh and
# scripts/*.sh (just has no built-in scripts-directory convention — this is
# a project convention, not magic). `just` sets $1, $2, ... from a recipe's
# declared parameters (in order, including defaults) when `positional-arguments`
# is set, so a one-line `./just/foo.sh "$@"` body forwards them faithfully.

default:
  @just --list

# All SOPS recipes (sops-edit, sops-config-gen) are private-repo-only now —
# all real SOPS files live there. Run them from the private checkout instead:
#   just -f "$PRIVATE_CONFIG_DIR/justfile" --working-directory "$PRIVATE_CONFIG_DIR" sops-edit FILE PATH VALUE

repl host='':
  ./scripts/nix.sh repl "{{host}}"

build-pkg pkg host='':
  ./just/build-pkg.sh "$@"

nixos-anywhere *args:
  ./scripts/nixos-install.sh local {{args}}

nixos-remote *args:
  ./scripts/nixos-install.sh remote {{args}}

init-host *args:
  ./scripts/init-host-config.sh {{args}}

alias fmt-nix := nixfmt
nixfmt:
  ./just/nixfmt.sh

# tofu formatting is private-repo-only now — run it from the private
# checkout: just -f "$PRIVATE_CONFIG_DIR/justfile" --working-directory "$PRIVATE_CONFIG_DIR" fmt-tofu
fmt: nixfmt
  @echo "Formatted nix files"

eval *args:
  ./scripts/nix.sh eval {{args}}

eval-hm *args:
  ./scripts/nix.sh eval --home-manager {{args}}

alias hm := home-manager
home-manager host='':
  ./just/home-manager.sh "$@"

nix-update *args:
  ./scripts/nix-update.sh {{args}}

deploy host='' *args:
  ./just/deploy.sh "$@"

renovate *args:
  ./just/renovate.sh "$@"

alias iso := build-iso
build-iso host='iso':
  ./scripts/build-installation-media.sh iso "{{host}}"

alias rpi := build-rpi-img
build-rpi-img *args='':
  ./just/build-rpi-img.sh "$@"

alias fetch-blobs := fetch-proprietary-garbage
fetch-proprietary-garbage *args:
  ./scripts/fetch-proprietary-garbage.sh {{args}}

# All tofu recipes (tofu, tofu-remote, tofu-yolo) are private-repo-only now —
# the tofu config itself lives there. Run them from the private checkout:
#   just -f "$PRIVATE_CONFIG_DIR/justfile" --working-directory "$PRIVATE_CONFIG_DIR" tofu-remote rofl-14 apply -auto-approve
