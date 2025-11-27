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
