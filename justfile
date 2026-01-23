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
    nix run nixpkgs#nixfmt -- "${files[@]}"
  else
    echo "No .nix files to format"
  fi

alias tofu-fmt := fmt-tofu
fmt-tofu:
  tofu -chdir=tofu fmt

fmt: nixfmt fmt-tofu
  @echo "Formatted nix files and tofu configs"

eval *args:
  ./scripts/nix.sh eval {{args}}

eval-hm *args:
  ./scripts/nix.sh eval --home-manager {{args}}

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

renovate *args:
  #!/usr/bin/env bash
  set -euo pipefail
  RENOVATE_TOKEN=${RENOVATE_TOKEN:-$(gh auth token)}
  if [[ -z "${RENOVATE_REPOSITORIES:-}" ]]
  then
    origin_url="$(git config --get remote.origin.url || true)"
    if [[ -z "$origin_url" ]]
    then
      echo "RENOVATE_REPOSITORIES is required (e.g. owner/repo)" >&2
      exit 1
    fi
    origin_path="$origin_url"
    if [[ "$origin_path" == *://* ]]
    then
      origin_path="${origin_path#*://}"
      origin_path="${origin_path#*/}"
    elif [[ "$origin_path" == *:* ]]
    then
      origin_path="${origin_path#*:}"
    fi
    origin_path="${origin_path%.git}"
    RENOVATE_REPOSITORIES="$origin_path"
  fi
  nix run nixpkgs#renovate -- \
    --platform github \
    --token "$RENOVATE_TOKEN" \
    "$RENOVATE_REPOSITORIES" \
    {{args}}

alias iso := build-iso
build-iso host='iso':
  ./scripts/build-installation-media.sh iso "{{host}}"

alias rpi := build-rpi-img
build-rpi-img host='pica4':
  ./scripts/build-installation-media.sh sd-image "{{host}}"

alias fetch-blobs := fetch-proprietary-garbage
fetch-proprietary-garbage *args:
  ./scripts/fetch-proprietary-garbage.sh {{args}}

tofu *args:
  ./tofu/tofu.sh {{args}}

alias tofu-deploy-all := tofu-yolo
tofu-yolo host='' *args:
  zhj nixos::rebuild-all-from-rofl {{args}}
