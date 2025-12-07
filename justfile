set shell := ["bash", "-euo", "pipefail", "-c"]

default:
  @just --list

sops-config-gen *args:
  ./secrets/sops-config-gen.sh {{args}}

repl host='':
  ./nix.sh repl "{{host}}"

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
  ./nixos-install.sh local {{args}}

nixos-remote *args:
  ./nixos-install.sh remote {{args}}

init-host *args:
  ./init-host-config.sh {{args}}

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
  ./nix.sh eval {{params}}

eval-hm *params:
  ./nix.sh eval --home-manager {{params}}

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

build-iso host='iso':
  ./build-installation-media.sh iso "{{host}}"

build-rpi-img host='pica4':
  ./build-installation-media.sh sd-image "{{host}}"

tofu *args:
  ./tofu/tofu.sh {{args}}

tofu-yolo host='' *args:
  zhj nixos::rebuild-all-from-rofl {{args}}
