set shell := ["bash", "-euo", "pipefail", "-c"]
set positional-arguments

default:
  @just --list

sops-config-gen *args:
  ./secrets/sops-config-gen.sh {{args}}

# Set/edit a value in a SOPS file by dotted path.
#   just sops-edit FILE PATH VALUE
# VALUE is taken literally, or read from a file with the `file:` prefix.
# Examples:
#   just sops-edit secrets/shared.sops.yaml httpd.password 'mysecret1234' # gitleaks:allow
#   just sops-edit secrets/shared.sops.yaml users.pschmitt.password file:./hash.txt
#   just sops-edit secrets/shared.sops.yaml ssh.hosts.0 'first-array-entry'
alias sops-set := sops-edit
sops-edit file path value:
  #!/usr/bin/env bash
  set -euo pipefail

  file="$1"
  path="$2"
  raw="$3"

  if [[ ! -f "$file" ]]
  then
    echo "error: SOPS file not found: $file" >&2
    exit 1
  fi

  # Make sure an age key is available, even from CLI contexts without
  # ~/.config/sops/age/keys.txt (matches CLAUDE.md guidance).
  if [[ -z "${SOPS_AGE_KEY:-}" && ! -f "${SOPS_AGE_KEY_FILE:-$HOME/.config/sops/age/keys.txt}" ]]
  then
    if command -v ssh-to-age >/dev/null && [[ -f "$HOME/.ssh/id_ed25519" ]]
    then
      SOPS_AGE_KEY="$(ssh-to-age --private-key -i "$HOME/.ssh/id_ed25519")"
      export SOPS_AGE_KEY
    fi
  fi

  # Resolve the value. `file:<path>` reads the contents verbatim, otherwise
  # the argument is used literally. jq turns it into a JSON-encoded string so
  # quotes, newlines and other special characters are handled correctly.
  if [[ "$raw" == file:* ]]
  then
    valuefile="${raw#file:}"
    if [[ ! -f "$valuefile" ]]
    then
      echo "error: value file not found: $valuefile" >&2
      exit 1
    fi
    json_value="$(jq -Rs . < "$valuefile")"
  else
    json_value="$(printf '%s' "$raw" | jq -Rs .)"
  fi

  # Convert a dotted path (a.b.c) into SOPS index syntax (["a"]["b"]["c"]).
  # Purely-numeric segments become array indexes ([0]).
  sops_path=""
  IFS='.' read -ra segments <<< "$path"
  for seg in "${segments[@]}"
  do
    if [[ "$seg" =~ ^[0-9]+$ ]]
    then
      sops_path+="[$seg]"
    else
      sops_path+="[\"$seg\"]"
    fi
  done

  # Pick a sops that supports the `set` subcommand (added in 3.8.0). Older
  # versions silently treat `set` as a filename and drop into $EDITOR, which
  # hangs non-interactively and can clobber the file. Fall back to a pinned
  # nixpkgs sops when the one on PATH is too old or missing.
  if [[ -f /etc/profile.d/nix.sh ]]
  then
    source /etc/profile.d/nix.sh
  fi
  sops_cmd=(sops)
  have="$(command -v sops >/dev/null && sops --version 2>/dev/null | grep -oE '[0-9]+(\.[0-9]+){2}' | head -1)"
  if [[ -z "$have" || "$(printf '3.8.0\n%s\n' "$have" | sort -V | head -1)" != "3.8.0" ]]
  then
    echo "sops on PATH is too old or missing (${have:-none}); using 'nix run nixpkgs#sops'" >&2
    sops_cmd=(nix run nixpkgs#sops --)
  fi

  echo "Setting ${sops_path} in ${file}" >&2
  "${sops_cmd[@]}" set "$file" "$sops_path" "$json_value"

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

alias hm := home-manager
home-manager host='':
  #!/usr/bin/env bash
  set -euo pipefail
  if [[ -f /etc/profile.d/nix.sh ]]
  then
    source /etc/profile.d/nix.sh
  fi
  TARGET_HOST="{{host}}"
  if [[ -z "$TARGET_HOST" ]]
  then
    TARGET_HOST="${HOSTNAME:-$(hostname)}"
  fi

  BUILD_DIR="$(./scripts/copy-to-nix-tmp.sh hm)"
  trap "rm -rf '$BUILD_DIR'" EXIT

  OLD_PROFILE="$(readlink -f ~/.local/state/nix/profiles/home-manager 2>/dev/null || true)"

  nix_config='experimental-features = nix-command flakes'
  if command -v gh >/dev/null 2>&1
  then
    github_token="$(gh auth token 2>/dev/null || true)"
    if [[ -n "$github_token" ]]
    then
      nix_config+=$'\naccess-tokens = github.com='"$github_token"
    fi
  fi

  NIX_CONFIG="$nix_config" \
    nix run github:nix-community/home-manager -- \
      -b hm-backup \
      switch \
      --flake "${BUILD_DIR}#${TARGET_HOST}"

  NEW_PROFILE="$(readlink -f ~/.local/state/nix/profiles/home-manager 2>/dev/null || true)"
  if [[ -n "$OLD_PROFILE" && -n "$NEW_PROFILE" && "$OLD_PROFILE" != "$NEW_PROFILE" ]]
  then
    nvd --color always diff "$OLD_PROFILE" "$NEW_PROFILE"
  fi

nix-update *args:
  ./scripts/nix-update.sh {{args}}

deploy host='' *args:
  #!/usr/bin/env bash
  set -euxo pipefail
  if [[ -f /etc/profile.d/nix.sh ]]
  then
    source /etc/profile.d/nix.sh
  fi
  TARGET_HOST="{{host}}"
  set -- {{args}}
  if [[ -n "$TARGET_HOST" ]]
  then
    BUILD_DIR="$(./scripts/copy-to-nix-tmp.sh --host "$TARGET_HOST" nixos)"
    trap "ssh '$TARGET_HOST' rm -rf '$BUILD_DIR'" EXIT
    ssh "$TARGET_HOST" sudo nixos-rebuild switch --flake "${BUILD_DIR}#${TARGET_HOST}" --use-substitutes "$@"
  else
    TARGET_HOST="${HOSTNAME:-$(hostname)}"
    BUILD_DIR="$(./scripts/copy-to-nix-tmp.sh nixos)"
    trap "rm -rf '$BUILD_DIR'" EXIT
    sudo nix run nixpkgs#nixos-rebuild -- switch --flake "${BUILD_DIR}#${TARGET_HOST}" "$@"
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
build-rpi-img *args='':
  #!/usr/bin/env bash
  set -euxo pipefail
  build_host=""
  host="pica4"
  remaining=()
  args=({{args}})
  for ((i = 0; i < ${#args[@]}; i++)); do
    case "${args[$i]}" in
      --build-host)
        build_host="${args[$((i + 1))]}"
        ((i += 1))
        ;;
      -*)
        remaining+=("${args[$i]}")
        ;;
      *)
        host="${args[$i]}"
        ;;
    esac
  done
  if [[ -n "$build_host" ]]; then
    BUILD_DIR="$(./scripts/copy-to-nix-tmp.sh --host "$build_host" nixos)"
    trap "ssh '$build_host' rm -rf '$BUILD_DIR'" EXIT
    ssh "$build_host" \
      nix build --print-build-logs \
      "${BUILD_DIR}#nixosConfigurations.${host}.config.system.build.sdImage" \
      "${remaining[@]+"${remaining[@]}"}"
  else
    ./scripts/build-installation-media.sh sd-image "$host" "${remaining[@]+"${remaining[@]}"}"
  fi

alias fetch-blobs := fetch-proprietary-garbage
fetch-proprietary-garbage *args:
  ./scripts/fetch-proprietary-garbage.sh {{args}}

tofu *args:
  ./tofu/tofu.sh {{args}}

alias tofu-deploy-all := tofu-yolo
tofu-yolo host='' *args:
  zhj nixos::rebuild-all-from-rofl {{args}}
