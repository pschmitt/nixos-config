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

nix-eval-json *params:
  #!/usr/bin/env bash
  set -euxo pipefail
  set -- {{params}}
  TARGET_HOST="${HOSTNAME:-$(hostname)}"
  CONFIG_PATH="$1"
  shift || true
  if [[ "$#" -ge 1 ]]
  then
    TARGET_HOST="$CONFIG_PATH"
    CONFIG_PATH="$1"
    shift || true
  fi
  echo "Evaluating '${CONFIG_PATH}' for host '${TARGET_HOST}'"
  ./nix-eval-json.sh "$TARGET_HOST" "$CONFIG_PATH" "$@"

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
