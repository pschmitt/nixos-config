#!/usr/bin/env bash
# Client for ad-hoc build workers: disposable, encrypted OpenStack VMs that
# the control host creates on request (`rworker` there). This script runs
# it over SSH, pins each worker's SSH host key locally and wraps ssh, rsync
# and Nix builder use. See ../SKILL.md.

CONTROL_HOST="${RWORKER_HOST:-rofl-10}"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/rworker"
KNOWN_HOSTS="${STATE_DIR}/known_hosts"
# Set by -j/--json: JSON instead of the human-readable output.
JSON=""

usage() {
  cat <<EOF
Usage: $(basename "$0") ACTION [ARGS] [-j|--json]
       $(basename "$0") ACTION --help   (or: help ACTION)

-j, --json prints JSON instead of the human-readable output; every action
but ssh takes it (scripts and the MCP server use it).

Actions:
  up [--ttl 2h] [--flavor s1.xlarge] [--disk 150] [--ssh]
                       create a worker and wait until it is ready
  ls [-o json] [--watch [-n SECONDS]]
                       list all workers (ad-hoc and nixbot's pool)
  exec [UP_OPTIONS] [--sync SRC[:DEST]] [--fetch REMOTE[:LOCAL]] [--keep] -- CMD
                       one-shot: create a worker, run CMD, delete the worker
  down NAME            delete a worker
  prune [NAME...] [--all] [-y] [-n]
                       delete several ad-hoc workers (default: your own)
  extend NAME --ttl D  move the expiry to now + D (max 24h)
  ssh [USER@]NAME [SSH_ARGS...]
                       ssh to the worker (pinned host key); options such as
                       -L/-A and a command go straight to ssh
  ssh --create [UP_OPTIONS]
                       create a worker and log in (same as up --ssh)
  sync [USER@]NAME SRC [DEST]
                       rsync SRC to the worker (default ~/SRC basename)
  cp [USER@]NAME:REMOTE LOCAL | cp LOCAL [USER@]NAME:REMOTE
                       copy files or directories from/to a worker
  builder NAME         print a Nix builders line for the worker

Workers this host did not create (nixbot's pool, other hosts' ad-hoc
workers) are looked up on the control host on first use; you log in as
yourself there, as agent on your own ad-hoc workers.

Environment: RWORKER_HOST (default rofl-10), RWORKER_KEY (public key file,
default ~/.ssh/id_ed25519.pub), RWORKER_USER (SSH user override).
EOF
}

# Machine-readable command spec: the shell completions read it, and the
# rworker-completions flake check compares it with the dispatch below and
# with action_help. Keep all three in sync when adding an action or flag.
#   action NAME DESCRIPTION
#   flag ACTION FLAG[=VALUES] DESCRIPTION   (VALUES names a values line)
#   values NAME WORD...
#   worker ACTION...                        (first argument is a worker)
#   global FLAG DESCRIPTION                 (every action except ssh)
spec() {
  cat <<'SPEC'
action up create a worker and wait until it is ready
action ls list all workers (ad-hoc and pool)
action exec create a worker, run a command on it, delete it
action down delete an ad-hoc worker
action prune delete several ad-hoc workers (default: your own)
action extend move the expiry of an ad-hoc worker
action ssh ssh to a worker (pinned host key)
action sync rsync a directory to a worker
action builder print a Nix builders line for a worker
action cp copy files from or to a worker (NAME:PATH)
action help show the help of an action
flag up --ttl=duration lifetime, e.g. 90m or 2h
flag up --flavor=flavor OpenStack flavor
flag up --disk=size volume size in GiB
flag up --scratch scratch host, may live up to 7 days
flag up --ssh log in as soon as it is ready
flag exec --ttl=duration lifetime of the worker
flag exec --flavor=flavor OpenStack flavor
flag exec --disk=size volume size in GiB
flag exec --scratch scratch host, may live up to 7 days
flag exec --sync=path copy a directory to the worker first (SRC[:DEST])
flag exec --fetch=path copy a path back afterwards (REMOTE[:LOCAL])
flag exec --keep keep the worker afterwards
flag exec --keep-on-failure keep the worker if the command fails
flag ssh --create create a worker first (same as up --ssh; up's options follow)
flag ls -o=format output format
flag ls --watch redraw in place, marking changes
flag ls -n=interval refresh interval in seconds (with --watch)
flag extend --ttl=duration new lifetime from now
flag prune --all every ad-hoc worker, whoever owns it
flag down --force delete someone else's worker
flag extend --force extend someone else's worker
flag prune --yes do not ask
flag prune --dry-run only show what would be deleted
values duration 30m 1h 2h 4h 8h 24h
values flavor s1.large s1.xlarge s1.2xlarge
values size 100 150 250 500
values path
values format json
values interval 2 5 10 30
worker down extend ssh sync builder prune
global --json force JSON output
global -j short for --json
SPEC
}

# Help for one action, answered locally (never forwarded to the control host).
action_help() {
  local me
  me=$(basename "$0")
  case "$1" in
    up)
      cat <<EOF
Usage: $me up [--ttl DURATION] [--flavor FLAVOR] [--disk GIB] [--scratch] [--ssh]

Create an ad-hoc worker, wait until it is reachable (usually 1-4 min) and
print it as JSON (name, ip, host_key, user, expires_at, builder).

  --ttl DURATION   lifetime, e.g. 90m, 3h, 1h30m (default 2h). A worker that
                   is still busy when it expires is extended by 30 min at a
                   time, up to its maximum lifetime.
  --flavor FLAVOR  s1.large (8 vCPU/16 GiB), s1.xlarge (16/32, default),
                   s1.2xlarge (32/64)
  --disk GIB       volume size (default 150)
  --scratch        scratch host: maximum lifetime 7 days instead of 24 h
  --ssh            log in (as agent) as soon as it is ready

Example:
  w=\$($me up --ttl 3h --flavor s1.2xlarge | jq -r .name)
EOF
      ;;
    ls)
      cat <<EOF
Usage: $me ls [-o json] [-w|--watch [-n SECONDS]]

List all workers: ad-hoc ones (KIND adhoc) and nixbot's pool (KIND pool),
with status, flavor, NetBird IP, owner, time to expiry and age.

  -o json        print the raw JSON instead of the table
  -w, --watch    redraw the table in place every -n seconds (default 5),
                 marking rows: + new, ~ changed (status, IP, owner, expiry,
                 flavor), - gone. q quits, any other key refreshes now.
  -n SECONDS     refresh interval for --watch
EOF
      ;;
    exec)
      cat <<EOF
Usage: $me exec [UP_OPTIONS] [--sync SRC[:DEST]]... [--fetch REMOTE[:LOCAL]]...
          [--keep|--keep-on-failure] [--] CMD...

One-shot build: create an ad-hoc worker, optionally copy directories to it,
run CMD there as agent (live output; its exit code becomes ours), copy
results back and delete the worker again - also on errors and Ctrl-C.
Status messages go to stderr, the command's output to stdout.

  --ttl, --flavor, --disk, --scratch   as for up
  --sync SRC[:DEST]      rsync SRC to the worker before running (DEST
                         defaults to SRC's basename); repeatable
  --fetch REMOTE[:LOCAL] rsync REMOTE (relative to agent's home) back
                         afterwards, even if CMD failed; repeatable
  --keep                 do not delete the worker
  --keep-on-failure      keep it only when CMD fails (for debugging)
  --json                 print {name, exit_code, stdout, stderr} instead

Examples:
  $me exec --sync .:src -- 'cd src && nix develop -c cargo build --release'
  $me exec --flavor s1.2xlarge --sync .:app --fetch app/out:./out -- 'cd app && ./build.sh'
EOF
      ;;
    down)
      cat <<EOF
Usage: $me down NAME [--force]

Delete an ad-hoc worker with its volume and NetBird peer. Nothing on it
survives; copy results off first. Pool workers belong to the autoscaler.

Workers of another owner (\$USER@host, see ls) are refused unless --force.
EOF
      ;;
    prune)
      cat <<EOF
Usage: $me prune [NAME...] [--all] [-y|--yes] [-n|--dry-run]

Delete several ad-hoc workers at once: the named ones, or else all of yours
(owner \$USER@\$(hostname)); --all deletes every ad-hoc worker, whoever owns
it. nixbot's pool workers are never pruned.

Lists the workers and asks first; --yes skips the question (required
without a terminal). --dry-run only lists them.
EOF
      ;;
    extend)
      cat <<EOF
Usage: $me extend NAME --ttl DURATION [--force]

Set the expiry of an ad-hoc worker to now + DURATION (e.g. 2h), capped at
its maximum lifetime (24 h, or 7 days for --scratch workers). Workers of
another owner are refused unless --force.
EOF
      ;;
    ssh)
      cat <<EOF
Usage: $me ssh [USER@]NAME [SSH_ARGS...]
       $me ssh --create [UP_OPTIONS]

SSH to a worker over NetBird with its pinned host key. Everything after the
name goes to ssh, so options and a command both work.

Default user: agent on ad-hoc workers this host created, yourself on all
others (RWORKER_USER overrides). Workers this host does not know yet are
looked up on the control host.

--create makes a new worker and logs in, like \`up --ssh\`; up's options
(--ttl, --flavor, --disk, --scratch) follow it.

Examples:
  $me ssh --create --ttl 4h
  $me ssh adhoc-1234abcd
  $me ssh pschmitt@adhoc-1234abcd sudo journalctl -b
  $me ssh adhoc-1234abcd -L 8080:localhost:8080
  $me ssh adhoc-1234abcd 'cd src && nix develop -c cargo build'
EOF
      ;;
    sync)
      cat <<EOF
Usage: $me sync [USER@]NAME SRC [DEST]

rsync the directory SRC to the worker (DEST defaults to SRC's basename in
the user's home). Mirrors with --delete and skips target/, .direnv/ and
result.
EOF
      ;;
    cp)
      cat <<EOF
Usage: $me cp [USER@]NAME:REMOTE LOCAL
       $me cp LOCAL [USER@]NAME:REMOTE

Copy a file or directory from a worker to this host, or the other way
round, like scp but with rsync (directories without -r, resumable, pinned
host key). REMOTE is relative to the user's home on the worker.

Examples:
  $me cp adhoc-1234abcd:rbw/target/release/rbw ./rbw
  $me cp adhoc-1234abcd:build/logs/ ./logs/
  $me cp ./patch.diff pschmitt@adhoc-1234abcd:/tmp/
EOF
      ;;
    builder)
      cat <<EOF
Usage: $me builder NAME

Print a Nix builders line for the worker, e.g.:
  nix build --max-jobs 0 --builders "\$($me builder NAME)" .#pkg
EOF
      ;;
    *)
      usage
      ;;
  esac
}

# Colors for human-readable output (none when piped or NO_COLOR is set).
paint() {
  local code="$1"
  shift
  if [[ -t 1 && -z "${NO_COLOR:-}" ]]
  then
    printf '\e[%sm%s\e[0m' "$code" "$*"
  else
    printf '%s' "$*"
  fi
}

ok() {
  printf '%s %s\n' "$(paint 32 '✔')" "$*"
}

# "in 1h 59m (14:13)" for an epoch timestamp.
fmt_expiry() {
  local at="$1" left
  left=$(( at - $(date +%s) ))
  if (( left <= 0 ))
  then
    printf 'expired (%s)' "$(date -d "@$at" +%H:%M)"
  else
    printf 'in %dh %dm (%s)' $(( left / 3600 )) $(( left % 3600 / 60 )) \
      "$(date -d "@$at" +%H:%M)"
  fi
}

remote() {
  # shellcheck disable=SC2029 # arguments are meant to expand locally
  ssh -o BatchMode=yes "$CONTROL_HOST" rworker "$(printf '%q ' "$@")"
}

state_file() {
  printf '%s/%s.json\n' "$STATE_DIR" "$1"
}

# Fetch a worker this host did not create (another host's, or nixbot's pool)
# from the control host, pin its host key and remember it.
adopt() {
  local name="$1" info me user
  info=$(remote ls | jq -c --arg n "$name" '.[] | select(.name == $n)') \
    || return 1
  if [[ -z "$info" ]]
  then
    printf 'No worker named %s\n' "$name" >&2
    return 1
  fi
  if [[ "$(jq -r '.ip // empty' <<< "$info")" == "" \
    || "$(jq -r '.host_key // empty' <<< "$info")" == "" ]]
  then
    printf '%s has no IP or host key yet (still booting?)\n' "$name" >&2
    return 1
  fi
  # agent's keys are the creator's; everyone else logs in as themselves.
  me="${USER}@$(hostname)"
  user="$USER"
  if [[ "$(jq -r .kind <<< "$info")" == adhoc \
    && "$(jq -r .owner <<< "$info")" == "$me" ]]
  then
    user=agent
  fi
  mkdir -p "$STATE_DIR" || return 1
  jq -c --arg u "$user" '{name, ip, host_key, user: $u, kind}' <<< "$info" \
    > "$(state_file "$name")" || return 1
  printf '%s %s\n' "$(jq -r .ip <<< "$info")" "$(jq -r .host_key <<< "$info")" \
    >> "$KNOWN_HOSTS"
}

worker_field() {
  local name="$1" field="$2" file
  if [[ -z "$name" ]]
  then
    printf 'Missing worker name\n' >&2
    return 2
  fi
  file=$(state_file "$name")
  if [[ ! -f "$file" ]]
  then
    adopt "$name" || return 1
  fi
  jq -er --arg f "$field" '.[$f]' "$file"
}

# SSH options for a worker. Host keys are pinned per worker *name*
# (HostKeyAlias): NetBird reuses IPs, and a stale entry must fail loudly
# rather than reach whichever worker holds that IP now.
ssh_opts() {
  local name="$1" key
  key=$(worker_field "$name" host_key) || return 1
  if ! grep -q -F -x "$name $key" "$KNOWN_HOSTS" 2>/dev/null
  then
    printf '%s %s\n' "$name" "$key" >> "$KNOWN_HOSTS"
  fi
  printf '%s\n' \
    -o "UserKnownHostsFile=${KNOWN_HOSTS}" \
    -o "HostKeyAlias=${name}" \
    -o StrictHostKeyChecking=yes \
    -o BatchMode=yes
}

forget() {
  local name="$1" ip
  ip=$(worker_field "$name" ip 2>/dev/null) || return 0
  if [[ -f "$KNOWN_HOSTS" ]]
  then
    ssh-keygen -R "$ip" -f "$KNOWN_HOSTS" >/dev/null 2>&1 || true
  fi
  rm -f "$(state_file "$name")"
}

cmd_up() {
  local key_file="${RWORKER_KEY:-$HOME/.ssh/id_ed25519.pub}" info name ip
  local login="" arg
  local -a args=()
  for arg in "$@"
  do
    if [[ "$arg" == --ssh ]]
    then
      login=1
    else
      args+=("$arg")
    fi
  done
  set -- "${args[@]}"
  if [[ ! -r "$key_file" ]]
  then
    printf 'Public key %s not readable (set RWORKER_KEY)\n' "$key_file" >&2
    return 2
  fi
  mkdir -p "$STATE_DIR" || return 1
  local started
  started=$(date +%s)
  info=$(remote up --ssh-key "$(cat "$key_file")" \
    --owner "${USER}@$(hostname)" "$@") || return 1
  name=$(jq -er .name <<< "$info") || return 1
  ip=$(jq -er .ip <<< "$info") || return 1
  jq -c '. + {user: "agent", kind: "adhoc"}' <<< "$info" > "$(state_file "$name")" \
    || return 1
  printf '%s %s\n' "$ip" "$(jq -er .host_key <<< "$info")" >> "$KNOWN_HOSTS"
  if [[ -n "$JSON" ]]
  then
    printf '%s\n' "$info"
    return 0
  fi
  local me
  me=$(basename "$0")
  ok "$(paint 36 "$name") is ready ($(( $(date +%s) - started ))s)"
  printf '  %-8s %s\n' \
    IP "$ip (NetBird)" \
    User agent \
    Flavor "$(jq -r '.flavor // "-"' <<< "$info")" \
    Expires "$(fmt_expiry "$(jq -r .expires_at <<< "$info")")" \
    SSH "$me ssh $name" \
    Builder "nix build --max-jobs 0 --builders \"\$($me builder $name)\" .#pkg"
  if [[ -n "$login" ]]
  then
    connect "$name"
  fi
}

# Log in right after `up`: NetBird may still be setting up the route to the
# fresh peer, so retry the connection for a little while.
connect() {
  local name="$1" ip opts i
  ip=$(worker_field "$name" ip) || return 1
  mapfile -t opts < <(ssh_opts "$name")
  for i in $(seq 1 10)
  do
    if ssh "${opts[@]}" -o ConnectTimeout=5 "agent@${ip}" true 2>/dev/null
    then
      break
    fi
    printf 'Waiting for %s to accept SSH (%d)...\n' "$name" "$i" >&2
    sleep 3
  done
  # shellcheck disable=SC2029 # no remote command, just the login
  ssh "${opts[@]}" "agent@${ip}"
}

# kubectl-style table from `ls` JSON (aligned, uncolored); empty when there
# are no workers.
table_plain() {
  local rows
  rows=$(jq -r --argjson now "$(date +%s)" '
    def dur(s):
      if s < 0 then "expired"
      elif s < 3600 then "\(s / 60 | floor)m"
      elif s < 86400 then "\(s / 3600 | floor)h\(s % 3600 / 60 | floor)m"
      else "\(s / 86400 | floor)d\(s % 86400 / 3600 | floor)h" end;
    def created: .created_at // "" | sub("\\.[0-9]+"; "") | sub("(?<z>Z?)$"; "Z")
      | if . == "Z" then null else (try fromdateiso8601 catch null) end;
    ["NAME", "KIND", "STATUS", "FLAVOR", "IP", "OWNER", "EXPIRES", "AGE"],
    (sort_by(.kind, .name)[] | [
      .name, .kind, .status, (.flavor // "-"), (.ip // "<none>"),
      (if (.owner // "") == "" then "-" else .owner end),
      (if (.expires_at // 0) > 0 then dur(.expires_at - $now) else "-" end),
      (created as $c | if $c then dur($now - $c) else "-" end)
    ]) | @tsv') || return 1
  if [[ $(wc -l <<< "$rows") -le 1 ]]
  then
    return 0
  fi
  column -t -s $'\t' <<< "$rows"
}

# kubecolor-like colors for a table_plain table (header on line 1).
colorize() {
  local bold=$'\e[1m' green=$'\e[32m' yellow=$'\e[33m' red=$'\e[31m'
  local cyan=$'\e[36m' reset=$'\e[0m'
  sed -E \
    -e "1s/.*/${bold}&${reset}/" \
    -e "2,\$s/ (ACTIVE) / ${green}\1${reset} /" \
    -e "2,\$s/ (BUILD|REBUILD|RESIZE|DELETING) / ${yellow}\1${reset} /" \
    -e "2,\$s/ (ERROR|SHUTOFF|DELETED) / ${red}\1${reset} /" \
    -e "2,\$s/ (expired) / ${red}\1${reset} /" \
    -e "2,\$s/ ([0-9]+m) ( +[0-9]+[mhd])/ ${yellow}\1${reset}\2/" \
    -e "2,\$s/^([^ ]+)/${cyan}\1${reset}/"
}

render_table() {
  local rows
  rows=$(table_plain) || return 1
  if [[ -z "$rows" ]]
  then
    printf 'No workers found.\n'
  elif [[ -t 1 && -z "${NO_COLOR:-}" ]]
  then
    colorize <<< "$rows"
  else
    printf '%s\n' "$rows"
  fi
}

# What counts as a change in --watch (not the ticking EXPIRES/AGE).
signatures() {
  jq -r '.[] | "\(.name)\t\(.kind)|\(.status)|\(.ip)|\(.owner)|\(.expires_at)|\(.flavor)"'
}

# `ls --watch`: redraw in place, like `kw` (kubectl-watch) and unlike
# `kubectl get --watch`, and mark what changed since the previous refresh:
# + new, ~ changed, - gone (shown once more).
watch_ls() {
  local interval="$1" color=""
  if [[ -t 1 && -z "${NO_COLOR:-}" ]]
  then
    color=1
  fi
  local green="" yellow="" red="" dim="" reset=""
  if [[ -n "$color" ]]
  then
    green=$'\e[32m'
    yellow=$'\e[33m'
    red=$'\e[31m'
    dim=$'\e[2m'
    reset=$'\e[0m'
  fi

  tput smcup 2>/dev/null || true
  tput civis 2>/dev/null || true
  trap 'tput cnorm 2>/dev/null; tput rmcup 2>/dev/null' EXIT
  trap 'exit 0' INT TERM

  declare -A prev_sig=() prev_row=()
  local first=1 json="" error="" key
  while true
  do
    if out=$(remote ls 2>&1)
    then
      json="$out"
      error=""
    else
      error="${out##*$'\n'}"
    fi

    local plain frame="" i=0 name marker line
    local -a plain_lines=() shown=()
    declare -A cur_sig=() cur_row=()
    while IFS=$'\t' read -r name sig
    do
      cur_sig[$name]="$sig"
    done < <(signatures <<< "${json:-[]}")
    plain=$(table_plain <<< "${json:-[]}")
    if [[ -n "$plain" ]]
    then
      mapfile -t plain_lines <<< "$plain"
      if [[ -n "$color" ]]
      then
        mapfile -t shown < <(colorize <<< "$plain")
      else
        shown=("${plain_lines[@]}")
      fi
    fi

    frame+="$(printf 'Every %ss: rworker ls    %s    %d workers    (q quits, any key refreshes)' \
      "$interval" "$(date +%T)" "${#cur_sig[@]}")"$'\n'
    if [[ -n "$error" ]]
    then
      frame+="${red}update failed, showing the last state: ${error}${reset}"$'\n'
    fi
    frame+=$'\n'
    for i in "${!plain_lines[@]}"
    do
      line="${plain_lines[$i]}"
      name="${line%% *}"
      marker="  "
      if (( i > 0 ))
      then
        cur_row[$name]="$line"
        if [[ -z "$first" && -z "${prev_sig[$name]+x}" ]]
        then
          marker="${green}+${reset} "
        elif [[ -z "$first" && "${prev_sig[$name]}" != "${cur_sig[$name]}" ]]
        then
          marker="${yellow}~${reset} "
        fi
      fi
      frame+="${marker}${shown[$i]}"$'\n'
    done
    for name in "${!prev_row[@]}"
    do
      if [[ -z "${cur_sig[$name]+x}" ]]
      then
        frame+="${red}-${reset} ${dim}${prev_row[$name]}${reset}"$'\n'
      fi
    done
    if (( ${#plain_lines[@]} == 0 ))
    then
      frame+="No workers found."$'\n'
    fi

    # Home, draw, clear the rest: no flicker.
    printf '\e[H%s\e[J' "$frame"

    prev_sig=()
    prev_row=()
    for name in "${!cur_sig[@]}"
    do
      prev_sig[$name]="${cur_sig[$name]}"
    done
    for name in "${!cur_row[@]}"
    do
      prev_row[$name]="${cur_row[$name]}"
    done
    unset cur_sig cur_row
    first=""

    key=""
    if [[ -t 0 ]]
    then
      read -r -s -n 1 -t "$interval" key || true
    else
      # No keyboard (e.g. piped or in a script): just wait.
      sleep "$interval"
    fi
    if [[ "$key" == q || "$key" == Q ]]
    then
      return 0
    fi
  done
}

cmd_ls() {
  local json="" watch="" interval=5
  while [[ -n "${1:-}" ]]
  do
    case "$1" in
      -o)
        shift
        if [[ "${1:-}" != json ]]
        then
          printf 'Only -o json is supported\n' >&2
          return 2
        fi
        json=1
        ;;
      --json|-ojson)
        json=1
        ;;
      -w|--watch)
        watch=1
        ;;
      -n|--interval)
        shift
        if [[ ! "${1:-}" =~ ^[0-9]+$ ]] || (( ${1:-0} < 1 ))
        then
          printf 'Interval must be a whole number of seconds\n' >&2
          return 2
        fi
        interval="$1"
        ;;
      *)
        printf 'Unknown option: %s\n' "$1" >&2
        return 2
        ;;
    esac
    shift
  done

  if [[ -n "$watch" ]]
  then
    watch_ls "$interval"
    return
  fi
  local out
  out=$(remote ls) || return 1
  if [[ -n "$json" || -n "$JSON" ]]
  then
    printf '%s\n' "$out"
    return 0
  fi
  render_table <<< "$out"
}

cmd_prune() {
  local all="" yes="" dry="" names=() me info targets
  while [[ -n "${1:-}" ]]
  do
    case "$1" in
      --all)
        all=1
        ;;
      -y|--yes)
        yes=1
        ;;
      -n|--dry-run)
        dry=1
        ;;
      -*)
        printf 'Unknown option: %s\n' "$1" >&2
        return 2
        ;;
      *)
        names+=("$1")
        ;;
    esac
    shift
  done

  me="${USER}@$(hostname)"
  info=$(remote ls) || return 1
  targets=$(jq -r --arg me "$me" --argjson all "${all:-false}" \
    --args '[.[] | select(.kind == "adhoc")]
      | if ($ARGS.positional | length) > 0
        then map(select(.name as $n | $ARGS.positional | index($n)))
        elif $all then .
        else map(select(.owner == $me)) end
      | .[] | "\(.name)\t\(.owner // "-")"' "${names[@]}" <<< "$info") \
    || return 1

  if [[ -z "$targets" ]]
  then
    if [[ -n "$JSON" ]]
    then
      printf '[]\n'
    else
      printf 'Nothing to prune.\n'
    fi
    return 0
  fi
  if [[ -n "$JSON" && -n "$dry" ]]
  then
    jq -R -s -c 'split("\n") | map(select(length > 0) | split("\t")
      | {name: .[0], owner: .[1], deleted: false})' <<< "$targets"
    return 0
  fi
  if [[ -z "$JSON" ]]
  then
    printf 'Ad-hoc workers to delete:\n'
    column -t -s $'\t' <<< "$targets" | sed 's/^/  /'
  fi
  if [[ -n "$dry" ]]
  then
    return 0
  fi
  if [[ -z "$yes" ]]
  then
    if [[ ! -t 0 ]]
    then
      printf 'Not a terminal: pass --yes to delete\n' >&2
      return 2
    fi
    local answer
    read -r -p 'Delete them? [y/N] ' answer
    if [[ "$answer" != [yY]* ]]
    then
      printf 'Aborted.\n'
      return 1
    fi
  fi

  local name owner failed="" results=()
  while IFS=$'\t' read -r name owner
  do
    if remote down "$name" --owner "${USER}@$(hostname)" --force > /dev/null
    then
      forget "$name"
      results+=("$(jq -nc --arg n "$name" --arg o "$owner" '{name: $n, owner: $o, deleted: true}')")
      [[ -n "$JSON" ]] || ok "deleted $(paint 36 "$name")"
    else
      failed=1
      results+=("$(jq -nc --arg n "$name" --arg o "$owner" '{name: $n, owner: $o, deleted: false}')")
    fi
  done <<< "$targets"
  if [[ -n "$JSON" ]]
  then
    printf '%s\n' "${results[@]}" | jq -s -c .
  fi
  if [[ -n "$failed" ]]
  then
    return 1
  fi
}

cmd_exec() {
  local keep="" keep_failed="" up_args=() syncs=() fetches=() cmd=()
  while [[ -n "${1:-}" ]]
  do
    case "$1" in
      --ttl|--flavor|--disk)
        if [[ -z "${2:-}" ]]
        then
          printf '%s needs a value\n' "$1" >&2
          return 2
        fi
        up_args+=("$1" "$2")
        shift
        ;;
      --scratch)
        up_args+=("$1")
        ;;
      --sync|--fetch)
        if [[ -z "${2:-}" ]]
        then
          printf '%s needs a path\n' "$1" >&2
          return 2
        fi
        if [[ "$1" == --sync ]]
        then
          syncs+=("$2")
        else
          fetches+=("$2")
        fi
        shift
        ;;
      --keep)
        keep=1
        ;;
      --keep-on-failure)
        keep_failed=1
        ;;
      --)
        shift
        cmd=("$@")
        break
        ;;
      -*)
        printf 'Unknown option: %s\n' "$1" >&2
        return 2
        ;;
      *)
        cmd=("$@")
        break
        ;;
    esac
    shift
  done
  if (( ${#cmd[@]} == 0 ))
  then
    printf 'Missing command (see %s exec --help)\n' "$(basename "$0")" >&2
    return 2
  fi

  local json="$JSON" info name ip
  info=$(JSON=1 cmd_up "${up_args[@]}") || return 1
  name=$(jq -er .name <<< "$info") || return 1
  ip=$(jq -er .ip <<< "$info") || return 1
  printf '%s %s is ready\n' "$(paint 32 '✔')" "$name" >&2

  local rc=0 opts out_file err_file
  mapfile -t opts < <(ssh_opts "$name")
  # Delete the worker however we leave (also Ctrl-C), unless asked not to.
  EXEC_WORKER="$name"
  EXEC_KEEP="$keep"
  trap 'exec_cleanup' EXIT
  trap 'exit 130' INT TERM

  local item src dest
  for item in "${syncs[@]}"
  do
    src="${item%%:*}"
    dest=""
    if [[ "$item" == *:* ]]
    then
      dest="${item#*:}"
    fi
    JSON=1 cmd_sync "$name" "$src" ${dest:+"$dest"} > /dev/null || return 1
    printf '%s synced %s\n' "$(paint 32 '✔')" "$item" >&2
  done

  # shellcheck disable=SC2029 # the command is the caller's, run as given
  if [[ -n "$json" ]]
  then
    out_file=$(mktemp)
    err_file=$(mktemp)
    ssh "${opts[@]}" "agent@${ip}" "${cmd[@]}" > "$out_file" 2> "$err_file" || rc=$?
  else
    ssh "${opts[@]}" "agent@${ip}" "${cmd[@]}" || rc=$?
  fi

  local remote_path local_path
  for item in "${fetches[@]}"
  do
    remote_path="${item%%:*}"
    local_path="$(basename "$remote_path")"
    if [[ "$item" == *:* ]]
    then
      local_path="${item#*:}"
    fi
    if rsync -a -e "ssh ${opts[*]}" "agent@${ip}:${remote_path}" "$local_path"
    then
      printf '%s fetched %s to %s\n' "$(paint 32 '✔')" "$remote_path" "$local_path" >&2
    else
      printf 'Could not fetch %s\n' "$remote_path" >&2
    fi
  done

  if (( rc != 0 )) && [[ -n "$keep_failed" ]]
  then
    EXEC_KEEP=1
    printf 'Command failed (%d); keeping %s: %s ssh %s\n' "$rc" "$name" \
      "$(basename "$0")" "$name" >&2
  fi
  if [[ -n "$json" ]]
  then
    jq -n --arg n "$name" --argjson rc "$rc" --rawfile o "$out_file" \
      --rawfile e "$err_file" --argjson kept "${EXEC_KEEP:-0}" \
      '{name: $n, exit_code: $rc, stdout: $o, stderr: $e, kept: ($kept == 1)}'
    rm -f "$out_file" "$err_file"
  fi
  return "$rc"
}

# EXIT trap of cmd_exec: delete its worker unless it is to be kept.
exec_cleanup() {
  local rc=$?
  if [[ -n "${EXEC_WORKER:-}" && -z "${EXEC_KEEP:-}" ]]
  then
    remote down "$EXEC_WORKER" --owner "${USER}@$(hostname)" > /dev/null 2>&1 || true
    forget "$EXEC_WORKER"
    printf '%s deleted %s\n' "$(paint 32 '✔')" "$EXEC_WORKER" >&2
  fi
  EXEC_WORKER=""
  return "$rc"
}

cmd_extend() {
  local out name
  out=$(remote extend "$@" --owner "${USER}@$(hostname)") || return 1
  if [[ -n "$JSON" ]]
  then
    printf '%s\n' "$out"
    return 0
  fi
  name=$(jq -r .name <<< "$out") || return 1
  ok "$(paint 36 "$name") now expires $(fmt_expiry "$(jq -r .expires_at <<< "$out")"), at most until $(date -d "@$(jq -r .max_lifetime_end <<< "$out")" '+%a %H:%M')"
}

cmd_down() {
  if [[ -z "${1:-}" ]]
  then
    usage >&2
    return 2
  fi
  local name="$1" extra=()
  shift
  if [[ "${1:-}" == --force ]]
  then
    extra=(--force)
  fi
  remote down "$name" --owner "${USER}@$(hostname)" "${extra[@]}" > /dev/null || return 1
  forget "$name"
  set -- "$name"
  if [[ -n "$JSON" ]]
  then
    jq -nc --arg n "$1" '{name: $n, deleted: true}'
  else
    ok "deleted $(paint 36 "$1")"
  fi
}

# "[user@]name" -> sets TARGET_NAME and TARGET_USER (empty: per worker).
split_target() {
  TARGET_USER=""
  TARGET_NAME="$1"
  if [[ -z "$1" || "$1" == *@ && -z "${1#*@}" ]]
  then
    printf 'Missing worker name\n' >&2
    return 2
  fi
  if [[ "$1" == *@* ]]
  then
    TARGET_USER="${1%%@*}"
    TARGET_NAME="${1#*@}"
  fi
}

target_user() {
  if [[ -n "$TARGET_USER" ]]
  then
    printf '%s\n' "$TARGET_USER"
  elif [[ -n "${RWORKER_USER:-}" ]]
  then
    printf '%s\n' "$RWORKER_USER"
  else
    worker_field "$TARGET_NAME" user
  fi
}

cmd_ssh() {
  local name ip user opts
  if [[ -z "${1:-}" ]]
  then
    usage >&2
    return 2
  fi
  split_target "$1" || return 2
  shift
  name="$TARGET_NAME"
  ip=$(worker_field "$name" ip) || return 1
  user=$(target_user) || return 1
  mapfile -t opts < <(ssh_opts "$name")
  # shellcheck disable=SC2029 # the command is the caller's, run as given
  ssh "${opts[@]}" "${user}@${ip}" "$@"
}

cmd_sync() {
  local src="${2:-}" dest="${3:-}" name ip user opts
  if [[ -z "${1:-}" || -z "$src" ]]
  then
    usage >&2
    return 2
  fi
  split_target "$1" || return 2
  name="$TARGET_NAME"
  ip=$(worker_field "$name" ip) || return 1
  user=$(target_user) || return 1
  mapfile -t opts < <(ssh_opts "$name")
  dest="${dest:-$(basename "$(realpath "$src")")}"
  rsync -a --delete --exclude target/ --exclude .direnv/ --exclude result \
    -e "ssh ${opts[*]}" "${src%/}/" "${user}@${ip}:${dest}/" || return 1
  if [[ -n "$JSON" ]]
  then
    jq -nc --arg n "$name" --arg s "$src" --arg d "$dest" --arg u "$user" \
      '{name: $n, src: $s, dest: $d, user: $u}'
  else
    ok "synced $src to $(paint 36 "$name"):$dest"
  fi
}

cmd_cp() {
  local src="${1:-}" dst="${2:-}" remote local_path direction target ip user opts
  if [[ -z "$src" || -z "$dst" || -n "${3:-}" ]]
  then
    action_help cp >&2
    return 2
  fi
  # Exactly one side is NAME:PATH (a local path with ":" needs a ./ prefix).
  if [[ "$src" == *:* && "$src" != ./* && "$src" != /* ]]
  then
    direction=down
    remote="$src"
    local_path="$dst"
  elif [[ "$dst" == *:* && "$dst" != ./* && "$dst" != /* ]]
  then
    direction=up
    remote="$dst"
    local_path="$src"
  else
    printf 'One side must be [USER@]NAME:PATH\n' >&2
    return 2
  fi
  target="${remote%%:*}"
  split_target "$target" || return 2
  ip=$(worker_field "$TARGET_NAME" ip) || return 1
  user=$(target_user) || return 1
  mapfile -t opts < <(ssh_opts "$TARGET_NAME")
  local spec="${user}@${ip}:${remote#*:}"
  if [[ "$direction" == down ]]
  then
    rsync -a --partial -e "ssh ${opts[*]}" "$spec" "$local_path" || return 1
  else
    rsync -a --partial -e "ssh ${opts[*]}" "$local_path" "$spec" || return 1
  fi
  if [[ -n "$JSON" ]]
  then
    jq -nc --arg n "$TARGET_NAME" --arg s "$src" --arg d "$dst" --arg dir "$direction" \
      '{name: $n, src: $s, dest: $d, direction: $dir}'
  else
    ok "copied $src to $dst"
  fi
}

cmd_builder() {
  local name="${1:-}" ip key
  if [[ -z "$name" ]]
  then
    usage >&2
    return 2
  fi
  ip=$(worker_field "$name" ip) || return 1
  key=$(worker_field "$name" host_key | base64 -w0) || return 1
  local line
  line=$(printf 'ssh-ng://agent@%s x86_64-linux - 16 1 nixos-test,benchmark,big-parallel,kvm - %s' \
    "$ip" "$key")
  if [[ -n "$JSON" ]]
  then
    jq -nc --arg n "$name" --arg b "$line" '{name: $n, builder: $b}'
  else
    printf '%s\n' "$line"
  fi
}

main() {
  local action="${1:-}" arg
  case "$action" in
    __spec)
      spec
      return 0
      ;;
    -h|--help|help)
      if [[ -n "${2:-}" ]]
      then
        action_help "$2"
      else
        usage
      fi
      return 0
      ;;
    "")
      usage >&2
      return 2
      ;;
  esac
  shift
  # --json anywhere (but not for ssh, whose arguments are ssh's).
  if [[ "$action" != ssh ]]
  then
    local -a rest=()
    local in_cmd=""
    for arg in "$@"
    do
      if [[ -n "$in_cmd" ]]
      then
        rest+=("$arg")
      elif [[ "$arg" == --json || "$arg" == -j ]]
      then
        JSON=1
      else
        rest+=("$arg")
        # exec: everything from -- on belongs to the command.
        if [[ "$arg" == -- ]]
        then
          in_cmd=1
        fi
      fi
    done
    set -- "${rest[@]}"
  fi
  # `ACTION --help`, except for ssh, whose arguments belong to ssh once a
  # worker name is given.
  for arg in "$@"
  do
    # ssh and exec: arguments after the worker or command are not ours.
    if [[ "$arg" == -- ]]
    then
      break
    fi
    if [[ ( "$action" == ssh || "$action" == exec ) && "$arg" != -* ]]
    then
      break
    fi
    if [[ "$arg" == -h || "$arg" == --help ]]
    then
      action_help "$action"
      return 0
    fi
  done
  case "$action" in
    up)
      cmd_up "$@"
      ;;
    ls)
      cmd_ls "$@"
      ;;
    down)
      cmd_down "$@"
      ;;
    prune)
      cmd_prune "$@"
      ;;
    exec)
      cmd_exec "$@"
      ;;
    extend)
      cmd_extend "$@"
      ;;
    ssh)
      if [[ "${1:-}" == --create ]]
      then
        shift
        cmd_up "$@" --ssh
      else
        cmd_ssh "$@"
      fi
      ;;
    sync)
      cmd_sync "$@"
      ;;
    builder)
      cmd_builder "$@"
      ;;
    cp)
      cmd_cp "$@"
      ;;
    *)
      printf 'Unknown action: %s\n' "$action" >&2
      usage >&2
      return 2
      ;;
  esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
  main "$@"
fi

# vim: set ft=sh et ts=2 sw=2 :
