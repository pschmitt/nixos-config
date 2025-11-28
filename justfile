set shell := ["bash", "-euo", "pipefail", "-c"]

default:
  @just --list

sops-config-gen *args:
  ./secrets/sops-config-gen.sh {{args}}

repl host='':
  ./nix-repl.sh "{{host}}"

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
  ./nixos-anywhere.sh {{args}}

new-host *args:
  ./new-host.sh {{args}}

eval *params:
  #!/usr/bin/env bash
  set -euxo pipefail
  TARGET_HOST="${HOSTNAME:-$(hostname)}"
  set -- {{params}}
  if [[ $# -eq 1 ]]
  then
    set -- "$TARGET_HOST" "$1"
  fi
  ./nix-eval-json.sh "$@"

eval-hm *params:
  #!/usr/bin/env bash
  set -euxo pipefail
  TARGET_HOST="${HOSTNAME:-$(hostname)}"
  set -- {{params}}
  if [[ $# -eq 1 ]]
  then
    set -- "$TARGET_HOST" "$1"
  fi
  ./nix-eval-json.sh "$1" "$2" --home-manager "${@:3}"

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

build-iso host='iso' *args:
  @echo "Building ISO for host '{{host}}' with args: {{args}}"
  ./build-iso.sh {{host}} {{args}}

build-rpi-img host='pica4' *args:
  @echo "Building Raspberry Pi Image for host '{{host}}' with args: {{args}}"
  ./build-rpi-img.sh {{host}} {{args}}

tofu *args:
  ./tofu/tofu.sh {{args}}

tofu-yolo host='' *args:
  zhj nixos::rebuild-all-from-rofl {{args}}
