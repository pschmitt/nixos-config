#!/usr/bin/env bash

WORKER_NAME=""
WORKER_INFO=""
LEASE_NONCE=""
LEASE_STARTED=""
UPLOAD_MODE="auto"

usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS] build|shell|develop NIX_ARGS...
       $(basename "$0") [OPTIONS] remote-build [--refresh] [-L] --no-link
                         [--print-out-paths] FLAKE#ATTR...
       $(basename "$0") --down WORKER

Lease a disposable rworker, run "nix SUBCOMMAND --max-jobs 0 --builders LINE
NIX_ARGS..." against it and delete the worker afterwards, also on failure.
Nix evaluation still runs locally.

remote-build evaluates on the worker too: it locks each flake here and lets
the worker fetch the flake and its inputs itself (rworker setup nix gives the
worker this side's access-tokens, so private GitHub inputs work too). Only
what the worker cannot fetch is uploaded: a flake or input that only exists
here (a local path, git+file, ssh-only git). It then builds the locked
installables there and copies the outputs back.

Options:
  --ttl DURATION    worker lifetime backstop (default: 1h)
  --topic TEXT      what the worker is for
  --profile NAME    rworker profile
  --flavor NAME     OpenStack flavor
  --disk GIB        root disk size
  --system SYSTEM   platform to build for (default: aarch64-linux); the
                    worker must run it natively or via qemu-user binfmt
  --upload MODE     what remote-build uploads: auto (default; only what the
                    worker cannot fetch itself), all (every locked input,
                    fetched here) or none (nothing, the worker fetches all)
  --down WORKER     delete a worker left behind and exit
  -h, --help        show this help

Settings come from the options, else RWORKER_NIX_{CONTROLLER,KEY,TTL,PROFILE,
SYSTEM,UPLOAD}, else ~/.config/rworker-nix/config and then local.conf beside it
(key=value lines; local.conf wins):
  controller   ssh alias of the rworker controller (required); its address
               and pinned host key belong in ~/.ssh/config and known_hosts
  key          public key file ending in .pub (default ~/.ssh/id_ed25519.pub)
  aws_credentials
               read-only AWS credentials of this side's s3:// substituter;
               remote-build then lets the worker substitute from that cache
               (rworker nix-cache), else the worker builds what no public
               cache has (RWORKER_NIX_AWS_CREDENTIALS overrides it)
EOF
}

warn() {
  printf '%s: %s\n' "$(basename "$0")" "$*" >&2
}

note() {
  printf '%s: %s\n' "$(basename "$0")" "$*" >&2
}

trim() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "$value"
}

read_config_file() {
  local file="$1" line key value
  [[ -r "$file" ]] || return 0
  while IFS= read -r line || [[ -n "$line" ]]
  do
    line="${line%%#*}"
    [[ "$line" == *=* ]] || continue
    key=$(trim "${line%%=*}")
    value=$(trim "${line#*=}")
    case "$key" in
      controller) CFG_CONTROLLER="$value" ;;
      key) CFG_KEY="$value" ;;
      ttl) CFG_TTL="$value" ;;
      profile) CFG_PROFILE="$value" ;;
      aws_credentials) CFG_AWS_CREDENTIALS="$value" ;;
      system) CFG_SYSTEM="$value" ;;
      upload) CFG_UPLOAD="$value" ;;
      *) warn "ignoring unknown key '$key' in $file" ;;
    esac
  done < "$file"
}

read_config() {
  local dir="${XDG_CONFIG_HOME:-$HOME/.config}/rworker-nix"
  CFG_CONTROLLER="" CFG_KEY="" CFG_TTL="" CFG_PROFILE="" CFG_SYSTEM="" CFG_UPLOAD="" CFG_AWS_CREDENTIALS=""
  read_config_file "$dir/config"
  read_config_file "$dir/local.conf"
}

valid_word() {
  [[ "$1" =~ ^[A-Za-z0-9][A-Za-z0-9_.@:+-]*$ ]]
}

check_ssh_strictness() {
  local controller="$1" cfg key value sshopts
  if ! cfg=$(ssh -G -- "$controller")
  then
    warn "cannot resolve ssh configuration for '$controller'"
    return 1
  fi
  while read -r key value _
  do
    if [[ "${key,,}" == stricthostkeychecking ]]
    then
      case "${value,,}" in
        no|off|false|accept-new)
          warn "ssh config for '$controller' sets StrictHostKeyChecking=$value; refusing"
          return 1
          ;;
      esac
    fi
  done <<< "$cfg"
  sshopts="${NIX_SSHOPTS:-}"
  if [[ "${sshopts,,}" == *stricthostkeychecking* ]]
  then
    warn "NIX_SSHOPTS must not set StrictHostKeyChecking; refusing"
    return 1
  fi
}

# Settings this wrapper owns, in any spelling Nix accepts: NAME, extra-NAME,
# no-NAME.
reserved_setting() {
  local name="$1"
  name="${name#extra-}"
  name="${name#no-}"
  case "$name" in
    max-jobs|builders|builders-use-substitutes|store|eval-store)
      return 0
      ;;
  esac
  return 1
}

# Arguments after -c/--command/-- belong to the command Nix runs.
check_nix_args() {
  local arg name prev=""
  for arg in "$@"
  do
    name=""
    case "$arg" in
      -c|--command|--)
        return 0
        ;;
      --option=*)
        name="${arg#--option=}"
        name="${name%%[= ]*}"
        ;;
      --*)
        name="${arg#--}"
        name="${name%%=*}"
        ;;
      -*j*)
        name="max-jobs"
        ;;
      -*)
        ;;
      *)
        if [[ "$prev" == --option ]]
        then
          name="$arg"
        fi
        ;;
    esac
    if [[ -n "$name" ]] && reserved_setting "$name"
    then
      warn "'$arg' conflicts with the worker setup"
      return 1
    fi
    prev="$arg"
  done
}

check_nix_config_env() {
  local line key
  while IFS= read -r line || [[ -n "$line" ]]
  do
    line="${line%%#*}"
    key=$(trim "${line%%=*}")
    key="${key,,}"
    if [[ -n "$key" ]] && reserved_setting "$key"
    then
      warn "NIX_CONFIG must not set max-jobs, builders or store; refusing"
      return 1
    fi
  done <<< "${NIX_CONFIG:-}"
}

# Deletes the leased worker, or the one a half-finished `up` left behind,
# found by the nonce in its topic.
destroy_worker() {
  local -a names=()
  local name listing failed=0 ok
  if [[ -n "$WORKER_NAME" ]]
  then
    names=("$WORKER_NAME")
  elif [[ -n "$LEASE_STARTED" ]]
  then
    if listing=$(rworker ls --json 2> /dev/null)
    then
      mapfile -t names < <(jq -r --arg nonce "$LEASE_NONCE" \
        '.[] | select(.kind == "adhoc" and ((.topic // "") | contains($nonce))) | .name' \
        <<< "$listing")
    else
      warn "could not list workers after a failed lease (topic nonce $LEASE_NONCE); it expires on its own"
      failed=1
    fi
  fi
  for name in "${names[@]}"
  do
    valid_word "$name" || continue
    ok=""
    for _ in 1 2
    do
      if rworker down "$name" > /dev/null
      then
        ok=1
        break
      fi
    done
    if [[ -z "$ok" ]]
    then
      warn "could not delete worker $name; run: $(basename "$0") --down $name (it expires on its own)"
      failed=1
    fi
  done
  return "$failed"
}

on_exit() {
  local rc=$?
  trap - EXIT INT TERM HUP
  if ! destroy_worker && (( rc == 0 ))
  then
    rc=1
  fi
  exit "$rc"
}

lease_worker() {
  local ttl="$1" topic="$2" profile="$3" flavor="$4" disk="$5" nix_cache="${6:-}" nix_auth="${7:-}"
  local -a args=(--json --ttl "$ttl" --topic "$topic" --no-niks3-token)
  [[ -n "$nix_cache" ]] || args+=(--no-nix-cache)
  # The access-tokens let the worker fetch private flake inputs itself.
  if [[ -n "$nix_auth" ]]
  then
    args+=(--nix-auth)
  else
    args+=(--no-nix-auth)
  fi
  local name
  [[ -z "$profile" ]] || args+=(--profile "$profile")
  [[ -z "$flavor" ]] || args+=(--flavor "$flavor")
  [[ -z "$disk" ]] || args+=(--disk "$disk")
  LEASE_STARTED=1
  WORKER_INFO=$(rworker up "${args[@]}") || return 1
  name=$(jq -er .name <<< "$WORKER_INFO") || return 1
  if ! valid_word "$name"
  then
    warn "controller returned an invalid worker name"
    return 1
  fi
  WORKER_NAME="$name"
}

# Prints the worker's Nix platform after checking it can build for TARGET.
probe_worker() {
  local name="$1" target="$2" arch="${2%-linux}" probe out="" line
  local worker_system="" extra="" binfmt=""
  # shellcheck disable=SC2016 # expanded by the worker's shell
  printf -v probe 'nix_c() { nix --extra-experimental-features nix-command config show "$1"; }; printf "system=%%s\\n" "$(nix_c system)"; printf "extra=%%s\\n" "$(nix_c extra-platforms)"; printf "binfmt=%%s\\n" "$(head -n 1 /proc/sys/fs/binfmt_misc/%s 2>/dev/null || head -n 1 /proc/sys/fs/binfmt_misc/qemu-%s 2>/dev/null)"' "$target" "$arch"
  for _ in $(seq 1 "${RWORKER_NIX_SSH_ATTEMPTS:-10}")
  do
    if out=$(rworker ssh "$name" "$probe")
    then
      break
    fi
    out=""
    sleep "${RWORKER_NIX_RETRY_DELAY:-3}"
  done
  if [[ -z "$out" ]]
  then
    warn "worker $name does not accept SSH with its pinned host key"
    return 1
  fi
  while IFS= read -r line
  do
    case "$line" in
      system=*) worker_system="${line#system=}" ;;
      extra=*) extra="${line#extra=}" ;;
      binfmt=*) binfmt="${line#binfmt=}" ;;
    esac
  done <<< "$out"
  if [[ -z "$worker_system" ]]
  then
    warn "could not read the Nix platform of worker $name"
    return 1
  fi
  if [[ "$worker_system" != "$target" ]]
  then
    if [[ " $extra " != *" $target "* ]]
    then
      warn "worker $name ($worker_system) lacks $target in extra-platforms (image too old?)"
      return 1
    fi
    if [[ "$binfmt" != enabled ]]
    then
      warn "worker $name has no enabled $target or qemu-$arch binfmt handler (got '${binfmt:-none}')"
      return 1
    fi
  fi
  printf '%s\n' "$worker_system"
}

# Prints the `rworker builder` line for TARGET once it matches the host key,
# address and platform the controller reported for the worker.
build_builder_line() {
  local name="$1" target="$2" worker_system="$3" info="$4"
  local line host_key decoded addr ip known_ip=""
  local -a f
  line=$(rworker builder "$name") || return 1
  read -r -a f <<< "$line"
  if (( ${#f[@]} != 8 )) || [[ "${f[0]}" != ssh-ng://agent@* ]]
  then
    warn "unexpected builder entry"
    return 1
  fi
  host_key=$(jq -er .host_key <<< "$info") || return 1
  if [[ ! "$host_key" =~ ^(ssh-ed25519|ssh-rsa|ecdsa-sha2-nistp[0-9]+)\ [A-Za-z0-9+/=]+$ ]] \
    || ! decoded=$(base64 --decode <<< "${f[7]}" 2> /dev/null) \
    || [[ "$decoded" != "$host_key" ]]
  then
    warn "builder host key does not match the key pinned from the controller's answer"
    return 1
  fi
  addr="${f[0]#ssh-ng://agent@}"
  while IFS= read -r ip
  do
    [[ "$ip" != "$addr" ]] || known_ip=1
  done < <(jq -r '[.ip, .ips.netbird, .ips.tailscale] | map(select(. != null and . != "")) | .[]' <<< "$info")
  if [[ -z "$known_ip" ]]
  then
    warn "builder address '$addr' is not an address of worker $name"
    return 1
  fi
  if [[ ",${f[1]}," != *",${worker_system},"* ]]
  then
    warn "builder entry advertises '${f[1]}' but the worker runs $worker_system"
    return 1
  fi
  f[1]="$target"
  printf '%s\n' "${f[*]}"
}

validate_lease_args() {
  local target="$1" ttl="$2" disk="$3" subcommand="$4"
  shift 4
  case "$subcommand" in
    build|shell|develop|remote-build)
      ;;
    "")
      warn "missing nix subcommand"
      usage >&2
      return 2
      ;;
    *)
      warn "unsupported nix subcommand '$subcommand' (build, shell, develop or remote-build)"
      return 2
      ;;
  esac
  if [[ ! "$target" =~ ^[a-z0-9_]+-linux$ ]]
  then
    warn "invalid --system '$target'"
    return 2
  fi
  if [[ ! "$ttl" =~ ^([0-9]+[smhd])+$ && ! "$ttl" =~ ^[0-9]+$ ]]
  then
    warn "invalid --ttl '$ttl'"
    return 2
  fi
  if [[ -n "$disk" && ! "$disk" =~ ^[0-9]+$ ]]
  then
    warn "invalid --disk '$disk'"
    return 2
  fi
  if [[ "$subcommand" == remote-build ]]
  then
    parse_remote_args "$@" || return 2
  else
    check_nix_args "$@" || return 2
  fi
  check_nix_config_env || return 2
}

# Sets REMOTE_REFRESH, REMOTE_LOGS, REMOTE_PRINT and REMOTE_INSTALLABLES from
# the remote-build arguments; anything else is refused.
parse_remote_args() {
  local arg no_link=""
  REMOTE_REFRESH="" REMOTE_LOGS="" REMOTE_PRINT=""
  REMOTE_INSTALLABLES=()
  for arg in "$@"
  do
    case "$arg" in
      --refresh)
        REMOTE_REFRESH=1
        ;;
      -L|--print-build-logs)
        REMOTE_LOGS=1
        ;;
      --print-out-paths)
        REMOTE_PRINT=1
        ;;
      --no-link)
        no_link=1
        ;;
      -*)
        warn "remote-build does not support '$arg'"
        return 1
        ;;
      *#*)
        if [[ "${arg%%#*}" == "" || "${arg#*#}" == "" || "$arg" =~ [[:space:]] ]]
        then
          warn "invalid installable '$arg'"
          return 1
        fi
        REMOTE_INSTALLABLES+=("$arg")
        ;;
      *)
        warn "remote-build needs FLAKE#ATTR installables (got '$arg')"
        return 1
        ;;
    esac
  done
  if [[ -z "$no_link" ]]
  then
    warn "remote-build needs --no-link: outputs are only copied back"
    return 1
  fi
  if (( ${#REMOTE_INSTALLABLES[@]} == 0 ))
  then
    warn "remote-build needs at least one FLAKE#ATTR"
    return 1
  fi
}

# The ssh-ng store URL of the worker, from its checked builder LINE.
worker_store_url() {
  local -a f
  read -r -a f <<< "$1"
  printf '%s?ssh-key=%s&base64-ssh-public-host-key=%s\n' "${f[0]}" "${f[2]}" "${f[7]}"
}

# Whether the worker can fetch a locked flake input itself: a hosted source
# (GitHub, GitLab, SourceHut) or an http(s)/git URL. Anything that only
# exists on this side (path, git+file, ssh-only git, mercurial) or that is
# unknown has to be uploaded. Takes the input's "locked" JSON.
remote_fetchable() {
  jq -e '
    (.type // "") as $type | (.url // "") as $url
    | ($type | IN("github", "gitlab", "sourcehut"))
      or (($type | IN("tarball", "file")) and ($url | test("^https?://")))
      or ($type == "git" and ($url | test("^(https?|git)://")))
  ' <<< "$1" > /dev/null 2>&1
}

# Fetches what the worker cannot fetch itself (UPLOAD_MODE auto), everything
# (all) or nothing (none) of the source and the locked inputs of FLAKE here
# and copies it to STORE. Inputs this side cannot fetch either are skipped:
# evaluation fetches lazily, so they only matter if the build uses them.
upload_flake() {
  local store="$1" flake="$2" meta locked path name bytes
  local -a refresh=() paths=()
  local remote=0
  [[ -z "$REMOTE_REFRESH" ]] || refresh=(--refresh)
  meta=$(nix flake metadata --json "${refresh[@]}" "$flake") || return 1
  if [[ "$UPLOAD_MODE" == all ]] \
    || { [[ "$UPLOAD_MODE" == auto ]] && ! remote_fetchable "$(jq -c .locked <<< "$meta")"; }
  then
    # metadata only reports the source's store path: a GitHub flake is
    # unpacked into the git cache, not into the store, so the copy below would
    # try to substitute it. prefetch puts it into the store.
    path=$(nix flake prefetch --json "${refresh[@]}" "$flake" | jq -er .storePath) || return 1
    paths=("$path")
  else
    remote=$((remote + 1))
  fi
  while IFS=$'\t' read -r name locked
  do
    if [[ "$UPLOAD_MODE" == none ]] \
      || { [[ "$UPLOAD_MODE" == auto ]] && remote_fetchable "$locked"; }
    then
      remote=$((remote + 1))
      continue
    fi
    if path=$(LOCKED="$locked" nix eval --raw --impure --expr \
      '(builtins.fetchTree (builtins.fromJSON (builtins.getEnv "LOCKED"))).outPath' 2> /dev/null)
    then
      paths+=("$path")
    else
      warn "skipping input '$name': cannot fetch it here"
    fi
  done < <(jq -r '.locks.nodes | to_entries[]
    | select(.value.locked != null)
    | "\(.key)\t\(.value.locked | del(.dir) | tojson)"' <<< "$meta")
  if (( ${#paths[@]} == 0 ))
  then
    note "$flake: the worker fetches all $remote sources itself, nothing to upload"
    return 0
  fi
  bytes=$(nix path-info --json "${paths[@]}" 2> /dev/null \
    | jq -r '[.. | .narSize? // empty] | add // 0') || bytes=0
  note "$flake: uploading ${#paths[@]} sources ($((bytes / 1048576)) MiB), the worker fetches $remote itself"
  nix copy --no-check-sigs --to "$store" "${paths[@]}"
}

# Locks the installables here, uploads their sources to the worker, builds them
# there and copies the outputs back. Prints the output paths on request.
remote_build() {
  local name="$1" store="$2" installable flake attr locked remote out path
  local -a refresh=() logs=() targets=() paths=()
  [[ -z "$REMOTE_REFRESH" ]] || refresh=(--refresh)
  [[ -z "$REMOTE_LOGS" ]] || logs=(-L)
  for installable in "${REMOTE_INSTALLABLES[@]}"
  do
    flake="${installable%%#*}"
    attr="${installable#*#}"
    locked=$(nix flake metadata --json "${refresh[@]}" "$flake" | jq -er .url) || {
      warn "cannot lock flake '$flake'"
      return 1
    }
    upload_flake "$store" "$flake" || {
      warn "cannot copy flake '$flake' to worker $name"
      return 1
    }
    targets+=("$locked#$attr")
  done
  printf -v remote '%q ' nix build --no-link --print-out-paths "${logs[@]}" "${targets[@]}"
  out=$(rworker ssh "$name" "$remote") || return 1
  while IFS= read -r path
  do
    [[ -n "$path" ]] || continue
    if [[ "$path" != /nix/store/* || "$path" =~ [[:space:]] ]]
    then
      warn "unexpected build output from worker: '$path'"
      return 1
    fi
    paths+=("$path")
  done <<< "$out"
  if (( ${#paths[@]} == 0 ))
  then
    warn "the worker build printed no output paths"
    return 1
  fi
  nix copy --no-check-sigs --from "$store" "${paths[@]}" || return 1
  if [[ -n "$REMOTE_PRINT" ]]
  then
    printf '%s\n' "${paths[@]}"
  fi
}

main() {
  local ttl="" topic="" profile="" flavor="" disk="" target="" down_name="" upload=""
  local controller key subcommand worker_system line value rc=0 aws_credentials nix_cache nix_auth
  local -a nix_args=()

  read_config
  while [[ $# -gt 0 ]]
  do
    case "$1" in
      -h|--help)
        usage
        return 0
        ;;
      --ttl|--topic|--profile|--flavor|--disk|--system|--upload|--down)
        if [[ -z "${2:-}" ]]
        then
          warn "$1 needs a value"
          usage >&2
          return 2
        fi
        case "$1" in
          --ttl) ttl="$2" ;;
          --topic) topic="$2" ;;
          --profile) profile="$2" ;;
          --flavor) flavor="$2" ;;
          --disk) disk="$2" ;;
          --system) target="$2" ;;
          --upload) upload="$2" ;;
          --down) down_name="$2" ;;
        esac
        shift 2
        ;;
      --)
        shift
        break
        ;;
      -*)
        warn "unknown option: $1"
        usage >&2
        return 2
        ;;
      *)
        break
        ;;
    esac
  done

  controller="${RWORKER_NIX_CONTROLLER:-$CFG_CONTROLLER}"
  key="${RWORKER_NIX_KEY:-${CFG_KEY:-$HOME/.ssh/id_ed25519.pub}}"
  ttl="${ttl:-${RWORKER_NIX_TTL:-${CFG_TTL:-1h}}}"
  profile="${profile:-${RWORKER_NIX_PROFILE:-$CFG_PROFILE}}"
  aws_credentials="${RWORKER_NIX_AWS_CREDENTIALS:-$CFG_AWS_CREDENTIALS}"
  target="${target:-${RWORKER_NIX_SYSTEM:-${CFG_SYSTEM:-aarch64-linux}}}"
  upload="${upload:-${RWORKER_NIX_UPLOAD:-${CFG_UPLOAD:-auto}}}"
  case "$upload" in
    auto|all|none) UPLOAD_MODE="$upload" ;;
    *)
      warn "--upload must be auto, all or none (got '$upload')"
      return 2
      ;;
  esac
  subcommand="${1:-}"
  nix_args=("${@:2}")

  if [[ -z "$controller" ]]
  then
    warn "no controller configured (set RWORKER_NIX_CONTROLLER or controller= in ~/.config/rworker-nix/local.conf)"
    return 2
  fi
  for value in "$controller" "$profile" "$flavor" "$down_name"
  do
    if [[ -n "$value" ]] && ! valid_word "$value"
    then
      warn "invalid value '$value'"
      return 2
    fi
  done
  if [[ "$key" != *.pub ]]
  then
    warn "the key must be a public key file ending in .pub (got '$key')"
    return 2
  fi
  if [[ -z "$down_name" ]]
  then
    validate_lease_args "$target" "$ttl" "$disk" "$subcommand" "${nix_args[@]}" || return
    if [[ ! -r "$key" ]]
    then
      warn "public key $key is not readable"
      return 2
    fi
  fi

  export RWORKER_HOST="$controller"
  export RWORKER_KEY="$key"
  export USER="${USER:-$(id -un)}"
  check_ssh_strictness "$controller" || return 1

  if [[ -n "$down_name" ]]
  then
    rworker down "$down_name"
    return
  fi

  LEASE_NONCE="rwn-$(od -An -N6 -tx1 /dev/urandom | tr -d ' \n')"
  trap on_exit EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  trap 'exit 129' HUP

  # remote-build evaluates and builds on the worker, which then needs this
  # side's private cache: some outputs exist nowhere else.
  nix_cache=""
  if [[ "$subcommand" == remote-build && -n "$aws_credentials" ]]
  then
    if [[ -r "$aws_credentials" ]]
    then
      export RWORKER_AWS_CREDENTIALS_FILE="$aws_credentials"
      nix_cache=1
    else
      warn "AWS credentials $aws_credentials are not readable; the worker gets no private cache"
    fi
  fi
  # Unless everything is uploaded, the worker fetches inputs itself and needs
  # this side's access-tokens for the private ones.
  nix_auth=""
  if [[ "$subcommand" == remote-build && "$UPLOAD_MODE" != all ]]
  then
    nix_auth=1
  fi
  lease_worker "$ttl" "full-nix rworker-nix ${topic:-$subcommand} $LEASE_NONCE" \
    "$profile" "$flavor" "$disk" "$nix_cache" "$nix_auth" || return 1
  worker_system=$(probe_worker "$WORKER_NAME" "$target") || return 1
  line=$(build_builder_line "$WORKER_NAME" "$target" "$worker_system" "$WORKER_INFO") \
    || return 1

  export NIX_SSHOPTS="-o StrictHostKeyChecking=yes -o BatchMode=yes${NIX_SSHOPTS:+ $NIX_SSHOPTS}"
  if [[ "$subcommand" == remote-build ]]
  then
    remote_build "$WORKER_NAME" "$(worker_store_url "$line")" || rc=$?
    return "$rc"
  fi
  nix "$subcommand" --max-jobs 0 --builders "$line" \
    --option builders-use-substitutes true "${nix_args[@]}" || rc=$?
  return "$rc"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
  main "$@"
fi

# vim: set ft=sh et ts=2 sw=2 :
