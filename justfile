set shell := ["bash", "-euo", "pipefail", "-c"]

default:
  @just --list

sops-config-gen *args:
  ./secrets/sops-config-gen.sh {{args}}

nix-repl host='':
  ./nix-repl.sh "{{host}}"

build-host-pkg pkg host='':
  #!/usr/bin/env bash
  set -euo pipefail
  host_arg="{{host}}"
  if [[ -z "$host_arg" ]]
  then
    host_arg="${CUSTOM_HOSTNAME:-${HOSTNAME:-$(hostname)}}"
  fi
  echo "Building pkg '{{pkg}}' for host '${host_arg}'"
  cmd=(nix build ".#nixosConfigurations.${host_arg}.pkgs.{{pkg}}")
  echo "+ ${cmd[*]}"
  "${cmd[@]}"

nixos-anywhere *args:
  ./nixos-anywhere.sh {{args}}

new-host *args:
  ./new-host.sh {{args}}

nix-eval-json *params:
  #!/usr/bin/env bash
  set -euo pipefail
  set -- {{params}}
  if [[ "$#" -eq 0 ]]
  then
    echo "Usage: just nix-eval-json <config_path> [<host>] [-- extra-args]" >&2
    exit 2
  fi
  host_arg="${CUSTOM_HOSTNAME:-${HOSTNAME:-$(hostname)}}"
  config_path="$1"
  shift || true
  if [[ "$#" -ge 1 ]]
  then
    host_arg="$config_path"
    config_path="$1"
    shift || true
  fi
  echo "Evaluating '${config_path}' for host '${host_arg}'"
  cmd=(./nix-eval-json.sh "$host_arg" "$config_path" "$@")
  echo "+ ${cmd[*]}"
  "${cmd[@]}"

build-iso *args:
  ./build-iso.sh {{args}}

build-rpi-img *args:
  ./build-rpi-img.sh {{args}}

tofu *args:
  ./tofu/tofu.sh {{args}}
