set shell := ["bash", "-euo", "pipefail", "-c"]

default:
  @just --list

sops-config-gen *args:
  ./secrets/sops-config-gen.sh {{args}}

repl host='':
  ./scripts/nix.sh repl "{{host}}"

build-pkg pkg host='':
  #!/usr/bin/env bash
  set -euxo pipefail
  TARGET_HOST="{{host}}"
  if [[ -z "$TARGET_HOST" ]]
  then
    TARGET_HOST="${HOSTNAME:-$(hostname)}"
  fi
  echo "Building pkg '{{pkg}}' for host '${TARGET_HOST}'"
  nix build ".#nixosConfigurations.${TARGET_HOST}.pkgs.{{pkg}}"

nixos-anywhere *args:
  ./scripts/nixos-install.sh local {{args}}

nixos-remote *args:
  ./scripts/nixos-install.sh remote {{args}}

init-host *args:
  ./scripts/init-host-config.sh {{args}}

alias fmt-nix := nixfmt
nixfmt:
  #!/usr/bin/env bash
  set -euo pipefail
  if [[ -f /etc/profile.d/nix.sh ]]
  then
    source /etc/profile.d/nix.sh
  fi
  mapfile -t files < <(find . -name '*.nix' -print)
  if [[ ${#files[@]} -gt 0 ]]
  then
    nix run nixpkgs#nixfmt-rfc-style -- "${files[@]}"
  else
    echo "No .nix files to format"
  fi

alias tofu-fmt := fmt-tofu
fmt-tofu:
  #!/usr/bin/env bash
  set -euo pipefail
  if [[ -f /etc/profile.d/nix.sh ]]
  then
    source /etc/profile.d/nix.sh
  fi
  tofu -chdir=tofu fmt

fmt: nixfmt fmt-tofu
  @echo "Formatted nix files and tofu configs"

eval *params:
  ./scripts/nix.sh eval {{params}}

eval-hm *params:
  ./scripts/nix.sh eval --home-manager {{params}}

nix-update *args:
  ./scripts/nix-update.sh {{args}}

deploy host='' *args:
  #!/usr/bin/env bash
  set -euxo pipefail
  TARGET_HOST="{{host}}"
  set -- {{args}}
  if [[ -n "$TARGET_HOST" ]]
  then
    zhj nixos::rebuild --target-host "$TARGET_HOST" "$@"
  else
    zhj nixos::rebuild "$@"
  fi

alias iso := build-iso
build-iso host='iso':
  ./scripts/build-installation-media.sh iso "{{host}}"

alias rpi := build-rpi-img
build-rpi-img host='pica4':
  ./scripts/build-installation-media.sh sd-image "{{host}}"

alias fetch-blobs := fetch-proprietary-garbage
fetch-proprietary-garbage:
  ./scripts/fetch-proprietary-garbage.sh

tofu *args:
  ./tofu/tofu.sh {{args}}

alias tofu-deploy-all := tofu-yolo
tofu-yolo host='' *args:
  zhj nixos::rebuild-all-from-rofl {{args}}
