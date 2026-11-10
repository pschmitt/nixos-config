#!/usr/bin/env bash
# Client for ad-hoc build workers: disposable, encrypted OpenStack VMs that
# the control host creates on request (`rworker` there). This script runs
# it over SSH, pins each worker's SSH host key locally and wraps ssh, rsync
# and Nix builder use. See ../SKILL.md.

CONTROL_HOST="${RWORKER_HOST:-rofl-10}"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/rworker"
# Nerd Font glyphs for the agent that created a worker (Codicons; the
# Nerd Fonts 3.4+ patched fonts have them). RWORKER_ICONS=0 turns them off.
ICONS=1
if [[ "${RWORKER_ICONS:-1}" == 0 ]]
then
  ICONS=""
fi
# jq: agent_label(a) is "<glyph> a" (just a without icons or agent).
# shellcheck disable=SC2016 # jq code, not shell
JQ_AGENT='def agent_label($a):
  if ($a // "") == "" then "-"
  elif $icons then
    ({claude: "", codex: "", shell: "", nixbot: "",
      copilot: "", gemini: "", agy: "", "browser-daemon": "󰊠",
      antigravity: ""}[$a] // "") + " " + $a
  else $a end;'
# Last `ls` answer of the control host, for the completions.
LS_CACHE="${STATE_DIR}/.ls.json"
KNOWN_HOSTS="${STATE_DIR}/known_hosts"
# Set by -j/--json: JSON instead of the human-readable output.
JSON=""
# Set by ls -o wide: the creator columns.
WIDE=""
# Colors, decided once: paint mostly runs inside $(...), where stdout is a
# pipe even when the user's terminal is not.
COLOR=""
if [[ -t 1 && -z "${NO_COLOR:-}" ]]
then
  COLOR=1
fi

usage() {
  cat <<EOF
Usage: $(basename "$0") ACTION [ARGS] [-j|--json]
       $(basename "$0") ACTION --help   (or: help ACTION)

-j, --json prints JSON instead of the human-readable output; every action
but ssh takes it (scripts and the MCP server use it).

Actions:
  start NAME [--name JOB] [--workdir DIR] -- CMD
                       start a registered job
  jobs NAME            list registered jobs
  ps [NAME]            show processes of running jobs on one or all workers
  logs [NAME [JOB]] [--lines N] [--follow] [--no-events]
                       show logs; follow includes lifecycle events by default
  events [--interval SECONDS]
                       stream worker and job lifecycle events
  register NAME JOB --log PATH
                       register an existing log file
  profiles             list available worker profiles
  up [--ttl 2h] [--flavor s1.xlarge] [--disk 150] [--topic TEXT]
     [--no-nix-cache] [--ssh [-l USER]]
                       create a worker and wait until it is ready
  ls [-o json|wide] [--watch [-n SECONDS]]
                       list all workers (ad-hoc and nixbot's pool)
  exec [UP_OPTIONS] [--sync SRC[:DEST]] [--fetch REMOTE[:LOCAL]] [--keep] -- CMD
                       one-shot: create a worker, run CMD, delete the worker
  inspect NAME [--boot]
                       show everything known about a worker
  down NAME            delete a worker
  prune [NAME...] [--all] [-y] [-n]
                       delete several ad-hoc workers (default: your own)
  extend NAME --ttl D  move the expiry to now + D (max 24h)
  ssh [-l USER | USER@]NAME [SSH_ARGS...]
                       ssh to the worker (pinned host key); options such as
                       -L/-A and a command go straight to ssh
  ssh --create [-l USER] [UP_OPTIONS]
                       create a worker and log in (same as up --ssh)
  sync [USER@]NAME SRC [DEST]
                       rsync SRC to the worker (default ~/SRC basename)
  cp [USER@]NAME:REMOTE LOCAL | cp LOCAL [USER@]NAME:REMOTE
                       copy files or directories from/to a worker
  builder NAME         print a Nix builders line for the worker
  nix-cache NAME [--dry-run]
                       let the worker substitute from this host's S3 cache

Workers this host did not create (nixbot's pool, other hosts' ad-hoc
workers) are looked up on the control host on first use; you log in as
yourself there, as agent on your own ad-hoc workers.

Environment: RWORKER_HOST (default rofl-10), RWORKER_KEY (public key file,
default ~/.ssh/id_ed25519.pub), RWORKER_USER (SSH user override),
RWORKER_ICONS=0 (no Nerd Font glyphs for the agent), NO_COLOR.
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
action start start a registered job
action jobs list registered jobs
action ps show processes of running jobs
action logs show job logs on one or all workers
action events stream worker and job lifecycle events
action register register an existing log file
action up create a worker and wait until it is ready
action profiles list available worker profiles
action ls list all workers (ad-hoc and pool)
action exec create a worker, run a command on it, delete it
action down delete an ad-hoc worker
action prune delete several ad-hoc workers (default: your own)
action extend move the expiry of an ad-hoc worker
action ssh ssh to a worker (pinned host key)
action sync rsync a directory to a worker
action builder print a Nix builders line for a worker
action nix-cache let a worker substitute from this host's S3 cache
action cp copy files from or to a worker (NAME:PATH)
action inspect show everything known about a worker
action help show the help of an action
flag start --name=job name the registered job
flag start --workdir=path working directory on the worker
flag logs --lines=count number of lines per job
flag logs --follow follow all jobs on all workers
flag logs --no-events suppress lifecycle events while following
flag events --interval=interval event polling interval
flag register --log=path absolute path to an existing log file
values job
values count 50 200 1000
values interval 1 2 5 10
flag up --ttl=duration lifetime, e.g. 90m or 2h
flag up --flavor=flavor OpenStack flavor
flag up --disk=size volume size in GiB
flag up --scratch scratch host, may live up to 7 days
flag up --ssh log in as soon as it is ready
flag up --nix-cache push this host's S3 cache settings (default when it has any)
flag up --no-nix-cache keep the S3 cache credentials off the worker
flag exec --nix-cache push this host's S3 cache settings (default when it has any)
flag exec --no-nix-cache keep the S3 cache credentials off the worker
flag nix-cache --dry-run only show what would be pushed
flag up -l=user log in as this user (with --ssh; default agent)
flag up --topic=topic what the worker is for (none unless given)
flag up --profile=profile worker profile (standard, browser-daemon or large-builder)
flag exec --topic=topic what the worker is for (none unless given)
flag exec --profile=profile worker profile (standard, browser-daemon or large-builder)
flag ls -o=format output format (wide adds PID, flavor, IP and cwd)
flag inspect --boot also show the worker's own boot metadata (over SSH)
flag exec --ttl=duration lifetime of the worker
flag exec --flavor=flavor OpenStack flavor
flag exec --disk=size volume size in GiB
flag exec --scratch scratch host, may live up to 7 days
flag exec --sync=path copy a directory to the worker first (SRC[:DEST])
flag exec --fetch=path copy a path back afterwards (REMOTE[:LOCAL])
flag exec --keep keep the worker afterwards
flag exec --keep-on-failure keep the worker if the command fails
flag ssh --create create a worker first (same as up --ssh; up's options follow)
flag ssh --profile=profile worker image profile when creating
flag ssh -l=user log in as this user (like ssh -l)
flag ls --watch redraw in place, marking changes
flag ls -n=interval refresh interval in seconds (with --watch)
flag extend --ttl=duration new lifetime from now
flag prune --all every ad-hoc worker, whoever owns it
flag down --force delete someone else's worker or a pool worker
flag extend --force extend someone else's worker
flag prune --yes do not ask
flag prune --dry-run only show what would be deleted
values duration 30m 1h 2h 4h 8h 24h
values flavor s1.large s1.xlarge s1.2xlarge
values profile standard browser-daemon large-builder
values size 100 150 250 500
values path
values format json wide
values topic
values user agent pschmitt nix-remote-builder
values interval 2 5 10 30
worker down extend ssh sync builder prune inspect nix-cache start jobs ps logs register
global --json force JSON output
global -j short for --json
SPEC
}

# Help for one action, answered locally (never forwarded to the control host).
action_help() {
  local me
  me=$(basename "$0")
  case "$1" in
    start)
      printf 'Usage: %s start WORKER [--name JOB] [--workdir DIR] -- COMMAND\n' "$me"
      ;;
    jobs)
      printf 'Usage: %s jobs WORKER\n' "$me"
      ;;
    ps)
      printf 'Usage: %s ps [WORKER]\n' "$me"
      ;;
    logs)
      printf 'Usage: %s logs [WORKER [JOB]] [--lines N] [--follow] [--no-events]\n' "$me"
      printf '       %s logs [-f]  # follow jobs and events on all workers\n' "$me"
      ;;
    events)
      printf 'Usage: %s events [--interval SECONDS]\n' "$me"
      ;;
    register)
      printf 'Usage: %s register WORKER JOB --log PATH\n' "$me"
      ;;
    profiles)
      printf 'Usage: %s profiles [--json]\n\nList profiles and their resources.\n' "$me"
      ;;
    up)
      cat <<EOF
Usage: $me up [--ttl DURATION] [--flavor FLAVOR] [--disk GIB] [--profile PROFILE] [--scratch] [--ssh]
          [--nix-cache|--no-nix-cache] [--topic TEXT] [-l USER]

Create an ad-hoc worker, wait until it is reachable (usually 1-4 min) and
print it as JSON (name, ip, host_key, user, expires_at, builder).

  --ttl DURATION   lifetime, e.g. 90m, 3h, 1h30m (default 2h). A worker that
                   is still in use when it expires stays until it has been
                   idle for 1h, up to its maximum lifetime.
  --flavor FLAVOR  s1.large (8 vCPU/16 GiB), s1.xlarge (16/32, default),
                   s1.2xlarge (32/64)
  --disk GIB       volume size (default 150)
  --profile NAME   standard (default), browser-daemon or large-builder
  --scratch        scratch host: maximum lifetime 7 days instead of 24 h
  --nix-cache      push the S3 cache settings (the default when this host's
                   Nix has an s3:// cache; fails loudly when it has none)
  --no-nix-cache   do not give the worker this host's S3 cache settings and
                   read-only key (see: $me help nix-cache). Without it they
                   are pushed whenever this host's Nix has an s3:// cache.
  --ssh            log in (as agent) as soon as it is ready
  -l USER          with --ssh: log in as USER (pschmitt, nix-remote-builder)
  --topic TEXT     what it is for (shown by ls and inspect; none unless
                   given)

The worker also records its creator: owner (\$USER@host), the agent
process (claude, codex, agy, opencode, ... and its PID), the agent session
id and the working directory. ls -o wide shows them; on the worker they are
in /run/rworker/metadata.json.

Example:
  w=\$($me up --ttl 3h --flavor s1.2xlarge | jq -r .name)
EOF
      ;;
    ls)
      cat <<EOF
Usage: $me ls [-o json|wide] [-w|--watch [-n SECONDS]]

List all workers: ad-hoc ones (KIND adhoc) and nixbot's pool (KIND pool),
with status, owner, creating agent, topic, time to expiry and age.
EXPIRES "grace 42m": expired but in use, deleted after 1h without use.
Pool workers have no TTL; EXPIRES shows what the autoscaler last saw:
busy, idle 12m (drained after 20m idle with nothing pending) or draining.

  -o json        print the raw JSON instead of the table
  -o wide        add the agent's PID, flavor, NetBird IP and cwd
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

  --ttl, --flavor, --disk, --profile, --scratch, --topic, --nix-cache, --no-nix-cache   as for up
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

Delete a worker with its volume and NetBird peer. Nothing on it survives;
copy results off first.

Workers of another owner (\$USER@host, see ls) are refused unless --force.
So are nixbot's pool workers (KIND pool): builds running on one fail; the
autoscaler replaces it from the current image when there is demand (handy
for a pool worker on an outdated image).
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
Usage: $me ssh [-l USER | USER@]NAME [SSH_ARGS...]
       $me ssh --create [-l USER] [UP_OPTIONS]

SSH to a worker over NetBird with its pinned host key. Everything after the
name goes to ssh, so options and a command both work.

Default user: agent on ad-hoc workers this host created, yourself on all
others (RWORKER_USER overrides). Workers this host does not know yet are
looked up on the control host.

--create makes a new worker and logs in, like \`up --ssh\`; up's options
(--ttl, --flavor, --disk, --profile, --scratch, --topic) follow it. -l USER picks the
login user, as with ssh (agent by default on a new worker).

Examples:
  $me ssh --create --ttl 4h
  $me ssh adhoc-1234abcd
  $me ssh pschmitt@adhoc-1234abcd sudo journalctl -b
  $me ssh --create -l pschmitt
  $me ssh adhoc-1234abcd -L 8080:localhost:8080
  $me ssh adhoc-1234abcd 'cd src && nix develop -c cargo build'
EOF
      ;;
    inspect)
      cat <<EOF
Usage: $me inspect NAME [--boot]

Show everything the control host knows about a worker: kind, status,
owner, who created it (agent, PID, session, topic, cwd), flavor, IP, host
key, created/expiry/grace/maximum lifetime and all server metadata.

  --boot   also show what the worker recorded at boot
           (/run/rworker/metadata.json, read over SSH)
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
    nix-cache)
      cat <<EOF
Usage: $me nix-cache NAME [--dry-run]
       $me up [--no-nix-cache] ... (does this right after creating the worker)

Let an ad-hoc worker substitute from the private S3 Nix cache, using this
host's own settings. up and exec do it by default when this host's Nix has
an s3:// substituter; --no-nix-cache keeps the worker free of the key.

Pushed over SSH (pinned host key), never through the OpenStack metadata
service and never via the control host:
  - this host's s3:// substituters and the trusted public keys, read with
    \`nix config show\`. Nothing else of nix.conf is copied (it can hold
    access-tokens and netrc paths), and neither are non-S3 substituters.
  - the AWS profile each s3:// URL names (profile=...) from
    \$AWS_SHARED_CREDENTIALS_FILE or ~/.aws/credentials; no other profile.
They land in /run/rworker-nix on the worker (tmpfs, agent-owned, 0700), so
they vanish with the worker. The worker's nix-daemon includes nix.conf from
there and restarts when it changes. Run it again after rotating the key.

Push a read-only key only: anyone with a shell on the worker (the agent user)
can read what you push. For builds through --builders, also set
builders-use-substitutes on this host, or this host fetches the inputs itself
and copies them over instead of letting the worker substitute.

  --dry-run   show the substituters, keys and profile names; push nothing
              (credentials are never printed)

A worker whose image predates this feature (no /run/rworker-nix) gets nothing;
the command says so and fails.
EOF
      ;;
    *)
      usage
      ;;
  esac
}

# Colors for human-readable non-help output (none when piped or NO_COLOR is set).
# Colors for help and usage output, including errors and redirected output,
# unless NO_COLOR is set:
# bold Usage and section headers, cyan flags with yellow arguments, and in
# the overview (MODE overview) green action names.
paint_help() {
  local mode="${1:-}"
  if [[ -n "${NO_COLOR:-}" ]]
  then
    cat
    return
  fi
  local b=$'\e[1m' c=$'\e[36m' y=$'\e[33m' g=$'\e[32m' r=$'\e[0m'
  local -a rules=(
    # Flags and placeholders inside the Usage lines (before Usage: is
    # painted, which these addresses match on).
    -e "/^(Usage:|       )/s/(^|[ [|])(--?[a-z][-a-z0-9]*)/\1${c}\2${r}/g"
    -e "/^(Usage:|       )/s/(^|[ [|=])([A-Z][A-Z_]+([.][.][.])?)([] |:]|$)/\1${y}\2${r}\4/g"
    -e "s/^(Usage:)/${b}\1${r}/"
    -e "s/^([A-Z][A-Za-z ,()-]*:)$/${b}\1${r}/"
    # Flags at the start of an option line, and their argument in capitals.
    -e "s/^(  +)(-[-a-zA-Z0-9]+(, -[-a-zA-Z0-9]+)*) ([A-Z][A-Z_.:]*)/\1${c}\2${r} ${y}\4${r}/"
    -e "s/^(  +)(-[-a-zA-Z0-9]+(, -[-a-zA-Z0-9]+)*)( |$)/\1${c}\2${r}\4/"
  )
  if [[ "$mode" == overview ]]
  then
    rules+=(-e "s/^(  )([a-z][a-z-]+)( |$)/\1${g}\2${r}\3/")
  fi
  sed -E "${rules[@]}"
}

# Print the help for the command that rejected its arguments. Help is
# colored even when it is redirected to stderr or piped, unless NO_COLOR is set.
show_help() {
  local action="${1:-}"
  if [[ -n "$action" ]]
  then
    action_help "$action" | paint_help
  else
    usage | paint_help overview
  fi
}

paint() {
  local code="$1"
  shift
  if [[ -n "$COLOR" ]]
  then
    printf '\e[%sm%s\e[0m' "$code" "$*"
  else
    printf '%s' "$*"
  fi
}

paint_vm() {
  paint 36 "$*"
}

paint_flavor() {
  paint 34 "$*"
}

paint_state() {
  local state="${1^^}" color="" bold=""
  case "$state" in
    ACTIVE|READY|SUCCEEDED|SUCCESS|COMPLETED)
      color=32
      bold=1
      ;;
    ERROR|FAILED|FAILURE)
      color=31
      bold=1
      ;;
    PENDING|QUEUED|BUILD|BUILDING|REBUILD|RESIZE|DELETING|BOOTING)
      color=33
      ;;
    SHUTOFF|DELETED)
      color=31
      ;;
    *)
      printf '%s' "$state"
      return
      ;;
  esac
  if [[ -n "$COLOR" && -n "$bold" ]]
  then
    printf '\e[1;%sm%s\e[0m' "$color" "$state"
  elif [[ -n "$COLOR" ]]
  then
    printf '\e[%sm%s\e[0m' "$color" "$state"
  else
    printf '%s' "$state"
  fi
}

paint_event_target() {
  local target="$1"
  if [[ "$target" == */* ]]
  then
    paint_vm "${target%%/*}"
    printf '/'
    paint 36 "${target#*/}"
  else
    paint_vm "$target"
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
  # One shared SSH connection to the control host (kept 10 min): repeated
  # calls (ls --watch, the completions' cache refresh) skip the handshake.
  mkdir -p "$STATE_DIR" 2>/dev/null
  # shellcheck disable=SC2029 # arguments are meant to expand locally
  ssh -o BatchMode=yes \
    -o ControlMaster=auto -o ControlPersist=10m \
    -o "ControlPath=${STATE_DIR}/control-%C" \
    "$CONTROL_HOST" rworker "$(printf '%q ' "$@")"
}

# `remote ls`, keeping the answer in $LS_CACHE for the completions.
remote_ls() {
  local out
  out=$(remote ls) || return 1
  mkdir -p "$STATE_DIR" 2>/dev/null \
    && printf '%s\n' "$out" > "${LS_CACHE}.tmp" 2>/dev/null \
    && mv -f "${LS_CACHE}.tmp" "$LS_CACHE" 2>/dev/null
  printf '%s\n' "$out"
}

# Hidden action for the completions: "NAME<TAB>DESCRIPTION" per worker
# (only ad-hoc ones for ACTION extend or prune), from the ls cache. Never
# waits on the network: a cache older than 30 s is refreshed in the
# background for the next TAB; without one, only the known names.
cmd_workers() {
  local action="${1:-}" age=999 file
  if [[ -r "$LS_CACHE" ]]
  then
    age=$(( $(date +%s) - $(stat -c %Y "$LS_CACHE") ))
  fi
  if (( age > 30 ))
  then
    ( remote_ls > /dev/null 2>&1 & ) 2>/dev/null
  fi
  if [[ ! -r "$LS_CACHE" ]]
  then
    for file in "$STATE_DIR"/*.json
    do
      [[ -e "$file" ]] || continue
      file="${file##*/}"
      printf '%s\t\n' "${file%.json}"
    done
    return 0
  fi
  jq -r --argjson now "$(date +%s)" --arg me "${USER}@$(hostname)" \
    --arg action "$action" \
    --argjson icons "$( [[ -n "$ICONS" ]] && echo true || echo false )" "$JQ_AGENT"'
    def dur(s):
      if s < 3600 then "\(s / 60 | floor)m"
      elif s < 86400 then "\(s / 3600 | floor)h\(s % 3600 / 60 | floor)m"
      else "\(s / 86400 | floor)d\(s % 86400 / 3600 | floor)h" end;
    .[]
    | select(($action != "extend" and $action != "prune") or .kind == "adhoc")
    | [ .kind,
        (if .agent then agent_label(.agent) else null end),
        .topic,
        (if .kind == "pool" then .pool_state
         elif (.grace_until // 0) > $now then "grace \(dur(.grace_until - $now))"
         elif (.expires_at // 0) > $now then "expires \(dur(.expires_at - $now))"
         elif (.expires_at // 0) > 0 then "expired"
         else null end),
        (if .status != "ACTIVE" then .status else null end),
        (if (.owner // "") != "" and .owner != $me then .owner else null end)
      ] as $parts
    | "\(.name)\t\([$parts[] | select(. != null and . != "")] | join(" · "))"
    ' "$LS_CACHE"
}

state_file() {
  printf '%s/%s.json\n' "$STATE_DIR" "$1"
}

# Fetch a worker this host did not create (another host's, or nixbot's pool)
# from the control host, pin its host key and remember it.
adopt() {
  local name="$1" info me user
  info=$(remote_ls | jq -c --arg n "$name" '.[] | select(.name == $n)') \
    || return 1
  if [[ -z "$info" ]]
  then
    printf 'No worker named %s\n' "$(paint_vm "$name")" >&2
    return 1
  fi
  if [[ "$(jq -r '.ip // empty' <<< "$info")" == "" \
    || "$(jq -r '.host_key // empty' <<< "$info")" == "" ]]
  then
    printf '%s has no IP or host key yet (still booting?)\n' "$(paint_vm "$name")" >&2
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
  # Out of the completions' cache right away, not at its next refresh.
  if [[ -w "$LS_CACHE" ]]
  then
    jq -c --arg n "$name" 'map(select(.name != $n))' "$LS_CACHE" \
      > "${LS_CACHE}.tmp" 2>/dev/null && mv -f "${LS_CACHE}.tmp" "$LS_CACHE"
  fi
  ip=$(worker_field "$name" ip 2>/dev/null) || return 0
  if [[ -f "$KNOWN_HOSTS" ]]
  then
    ssh-keygen -R "$ip" -f "$KNOWN_HOSTS" >/dev/null 2>&1 || true
  fi
  rm -f "$(state_file "$name")"
}

# --meta arguments describing who creates a worker: the agent process
# above us (claude, codex, agy, opencode, ...), its PID and session, the
# topic (only with --topic) and the working directory.
creator_meta() {
  local topic="$1" pid="$PPID" comm argv0 cand agent="" agent_pid="" session
  while [[ -n "$pid" && "$pid" -gt 1 && -z "$agent" ]]
  do
    comm=$(cat "/proc/${pid}/comm" 2>/dev/null) || break
    argv0=$(tr '\0' '\n' < "/proc/${pid}/cmdline" 2>/dev/null | head -n 1)
    # Nix wraps binaries: comm is then ".claude-wrapped".
    comm="${comm#.}"
    for cand in "${comm%-wrapped}" "${argv0##*/}"
    do
      case "$cand" in
        claude|codex|agy|antigravity|opencode|gemini|copilot|aider|cursor-agent|crush|goose|browser-daemon)
          agent="$cand"
          agent_pid="$pid"
          break
          ;;
      esac
    done
    if [[ -n "$agent" ]]
    then
      break
    fi
    pid=$(awk '/^PPid:/ { print $2 }' "/proc/${pid}/status" 2>/dev/null)
  done
  session="${CLAUDE_CODE_SESSION_ID:-${CODEX_THREAD_ID:-${CODEX_SESSION_ID:-}}}"
  if [[ -z "$agent" ]]
  then
    if [[ -n "${CLAUDE_CODE_SESSION_ID:-}" ]]
    then
      agent=claude
    elif [[ -n "${CODEX_THREAD_ID:-}${CODEX_SESSION_ID:-}" ]]
    then
      agent=codex
    else
      agent=shell
    fi
  fi
  printf '%s\n' --meta "agent=${agent}" --meta "cwd=${PWD}"
  if [[ -n "$agent_pid" ]]
  then
    printf '%s\n' --meta "agent_pid=${agent_pid}"
  fi
  if [[ -n "$session" ]]
  then
    printf '%s\n' --meta "agent_session=${session}"
  fi
  if [[ -n "$topic" ]]
  then
    printf '%s\n' --meta "topic=${topic}"
  fi
}

# The control host's stderr while `up` waits: "rworker-progress STAGE"
# lines become a spinner with the stage and elapsed time, redrawn in place
# on a terminal and gone once the worker is ready or failed; anything else
# is printed above it. Without a terminal only the other lines pass.
render_progress() {
  local frames='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏' i=0 stage="REQUESTING" line rc tty="" color frame state detail bold
  local start=$SECONDS
  if [[ -t 2 ]]
  then
    tty=1
  fi
  # paint() follows stdout; this draws on stderr.
  local esc=""
  if [[ -n "$tty" && -z "${NO_COLOR:-}" ]]
  then
    esc=1
  fi
  while true
  do
    if IFS= read -r -t 0.1 line
    then
      if [[ "$line" == "rworker-progress "* ]]
      then
        stage="${line#rworker-progress }"
      else
        if [[ -n "$tty" ]]
        then
          printf '\r\e[K' >&2
        fi
        if [[ -n "$esc" && "$line" =~ ^creating[[:space:]]+([^[:space:]]+)[[:space:]]+\(([^()]*)\)[[:space:]]+from[[:space:]]+image[[:space:]]+(.+)$ ]]
        then
          printf 'creating \e[36m%s\e[0m (\e[34m%s\e[0m) from image \e[35m%s\e[0m\n' \
            "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}" "${BASH_REMATCH[3]}" >&2
        else
          printf '%s\n' "$line" >&2
        fi
      fi
    else
      rc=$?
      # > 128: timed out (redraw); otherwise end of input.
      if (( rc <= 128 ))
      then
        break
      fi
    fi
    if [[ -n "$tty" ]]
    then
      state="$stage"
      detail=""
      if [[ "$stage" == *" · "* ]]
      then
        state="${stage%% · *}"
        detail="${stage#* · }"
      fi
      state="${state^^}"
      case "$state" in
        ACTIVE*|READY*|SUCCEEDED*|SUCCESS*|COMPLETED*)
          color=32
          bold=1
          ;;
        ERROR*|FAILED*|FAILURE*)
          color=31
          bold=1
          ;;
        SHUTOFF*|DELETED*)
          color=31
          bold=""
          ;;
        *)
          color=33
          bold=""
          ;;
      esac
      frame="${frames:i % ${#frames}:1}"
      i=$(( i + 1 ))
      if [[ -n "$esc" ]]
      then
        printf '\r\e[K\e[36m%s\e[0m ' "$frame" >&2
        if [[ -n "$bold" ]]
        then
          printf '\e[1;%sm%s\e[0m' "$color" "$state" >&2
        else
          printf '\e[%sm%s\e[0m' "$color" "$state" >&2
        fi
        if [[ -n "$detail" ]]
        then
          printf ' · \e[33m%s\e[0m' "$detail" >&2
        fi
        printf ' \e[2m(%ds)\e[0m' $(( SECONDS - start )) >&2
      else
        if [[ -n "$detail" ]]
        then
          printf '\r\e[K%s %s · %s (%ds)' "$frame" "$state" "$detail" $(( SECONDS - start )) >&2
        else
          printf '\r\e[K%s %s (%ds)' "$frame" "$state" $(( SECONDS - start )) >&2
        fi
      fi
    fi
  done
  if [[ -n "$tty" ]]
  then
    printf '\r\e[K' >&2
  fi
}

cmd_up() {
  local key_file="${RWORKER_KEY:-$HOME/.ssh/id_ed25519.pub}" info name ip
  local login="" login_user="" topic="" nix_cache=auto cache_info settings quiet_topic_warning=""
  local -a args=() meta=()
  while [[ -n "${1:-}" ]]
  do
    case "$1" in
      --ssh)
        login=1
        ;;
      --nix-cache)
        nix_cache=1
        ;;
      --no-nix-cache)
        nix_cache=""
        ;;
      -l)
        login_user="${2:-}"
        if [[ -z "$login_user" ]]
        then
          printf -- '-l needs a user\n' >&2
          show_help up >&2
          return 2
        fi
        shift
        ;;
      --topic)
        topic="${2:-}"
        shift
        ;;
      --quiet-topic-warning)
        quiet_topic_warning=1
        ;;
      *)
        args+=("$1")
        ;;
    esac
    shift
  done
  set -- "${args[@]}"
  mapfile -t meta < <(creator_meta "$topic")
  if [[ -z "$topic" && -z "$quiet_topic_warning" ]]
  then
    printf '%s no topic provided\n' "$(paint 33 '!')" >&2
  fi
  if [[ ! -r "$key_file" ]]
  then
    printf 'Public key %s not readable (set RWORKER_KEY)\n' "$key_file" >&2
    return 2
  fi
  mkdir -p "$STATE_DIR" || return 1
  local started
  started=$(date +%s)
  # stdout (the JSON) is captured through fd 3; stderr goes to the spinner.
  info=$(
    {
      remote up --ssh-key "$(cat "$key_file")" \
        --owner "${USER}@$(hostname)" "${meta[@]}" "$@" 2>&1 1>&3 3>&- \
        | render_progress
    } 3>&1
  ) || return 1
  name=$(jq -er .name <<< "$info") || return 1
  ip=$(jq -er .ip <<< "$info") || return 1
  jq -c '. + {user: "agent", kind: "adhoc"}' <<< "$info" > "$(state_file "$name")" \
    || return 1
  printf '%s %s\n' "$ip" "$(jq -er .host_key <<< "$info")" >> "$KNOWN_HOSTS"
  if [[ "$nix_cache" == auto ]]
  then
    # Default: push when this host's Nix has an s3:// substituter.
    nix_cache=""
    if settings=$(nix_cache_settings 2>/dev/null) \
      && [[ $(jq '.substituters | length' <<< "$settings") -gt 0 ]]
    then
      nix_cache=1
    fi
  fi
  if [[ -n "$nix_cache" ]]
  then
    # The cache is an optimisation: a failed push leaves a usable worker.
    # Whatever goes wrong, keep the worker and warn: keep a JSON result the
    # push printed (image-too-old), else make one.
    cache_info=$(push_nix_cache "$name") || true
    if ! jq -e 'type == "object"' <<< "$cache_info" > /dev/null 2>&1
    then
      cache_info='{"ok": false}'
    fi
    if [[ $(jq -r .daemon <<< "$cache_info") == image-too-old ]]
    then
      printf '%s image predates --nix-cache: nothing pushed to %s\n' \
        "$(paint 33 '!')" "$(paint_vm "$name")" >&2
    elif [[ $(jq -r .ok <<< "$cache_info") != true ]]
    then
      printf '%s could not set up the S3 cache on %s (the worker is fine); retry: %s nix-cache %s\n' \
        "$(paint 33 '!')" "$(paint_vm "$name")" "$(basename "$0")" "$name" >&2
    fi
    info=$(jq -c --argjson c "$cache_info" '. + {nix_cache: $c}' <<< "$info")
  fi
  if [[ -n "$JSON" ]]
  then
    printf '%s\n' "$info"
    return 0
  fi
  local me
  me=$(basename "$0")
  ok "$(paint_vm "$name") is $(paint '1;32' 'READY') $(paint 2 "($(( $(date +%s) - started ))s)")"
  local label value
  while IFS='|' read -r label value
  do
    printf '  %s %s\n' "$(paint 1 "$(printf '%-8s' "$label")")" "$value"
  done <<EOF
IP|$(paint 36 "$ip") $(paint 2 "(NetBird)")
User|agent
Profile|$(jq -r '.profile // "standard"' <<< "$info")
Flavor|$(paint_flavor "$(jq -r '.flavor // "-"' <<< "$info")")
Expires|$(paint 33 "$(fmt_expiry "$(jq -r .expires_at <<< "$info")")")
SSH|$(paint 32 "$me ssh") $(paint_vm "$name")
Builder|$(paint 32 'nix build --max-jobs 0 --builders') "$(paint 32 "$me builder") $(paint_vm "$name")" $(paint 32 '.#pkg')
EOF
  if [[ -n "$login" ]]
  then
    connect "$name" "${login_user:-agent}"
  fi
}

# Log in right after `up`: NetBird may still be setting up the route to the
# fresh peer, so retry the connection for a little while.
connect() {
  local name="$1" user="${2:-agent}" ip opts i
  ip=$(worker_field "$name" ip) || return 1
  mapfile -t opts < <(ssh_opts "$name")
  for i in $(seq 1 10)
  do
    if ssh "${opts[@]}" -o ConnectTimeout=5 "${user}@${ip}" true 2>/dev/null
    then
      break
    fi
    printf 'Waiting for %s to accept SSH (%d)...\n' "$(paint_vm "$name")" "$i" >&2
    sleep 3
  done
  # shellcheck disable=SC2029 # no remote command, just the login
  ssh "${opts[@]}" "${user}@${ip}"
}

# kubectl-style table from `ls` JSON (aligned, uncolored); empty when there
# are no workers.
table_plain() {
  local rows
  rows=$(jq -r --argjson now "$(date +%s)" --argjson wide "${WIDE:-false}" \
    --argjson icons "$( [[ -n "$ICONS" ]] && echo true || echo false )" "$JQ_AGENT"'
    def dur(s):
      if s < 0 then "expired"
      elif s < 3600 then "\(s / 60 | floor)m"
      elif s < 86400 then "\(s / 3600 | floor)h\(s % 3600 / 60 | floor)m"
      else "\(s / 86400 | floor)d\(s % 86400 / 3600 | floor)h" end;
    def created: .created_at // "" | sub("\\.[0-9]+"; "") | sub("(?<z>Z?)$"; "Z")
      | if . == "Z" then null else (try fromdateiso8601 catch null) end;
    def opt(v): if (v // "") == "" then "-" else v end;
    def expiry:
      if .kind == "pool" and .pool_state then
        (if .pool_state == "idle" and .last_busy
         then "idle \(dur($now - .last_busy))" else .pool_state end)
      elif (.grace_until // 0) > $now then "grace \(dur(.grace_until - $now))"
      elif (.expires_at // 0) > 0 then dur(.expires_at - $now)
      else "-" end;
    (["NAME", "KIND", "PROFILE", "STATUS", "OWNER", "AGENT", "TOPIC", "EXPIRES", "AGE"]
      + (if $wide then ["FLAVOR", "IP", "CWD"] else [] end)),
    (sort_by(.kind, .name)[] | [
      .name, .kind, (.profile // "standard"), (.status | ascii_upcase), opt(.owner),
      (if $wide and .agent_pid then "\(agent_label(.agent)) (\(.agent_pid))"
       else agent_label(.agent) end),
      opt(.topic), expiry,
      (created as $c | if $c then dur($now - $c) else "-" end)
    ] + (if $wide then [
      (.flavor // "-"), (.ip // "<none>"), opt(.cwd)
    ] else [] end)) | @tsv') || return 1
  if [[ $(wc -l <<< "$rows") -le 1 ]]
  then
    return 0
  fi
  column -t -s $'\t' <<< "$rows"
}

# kubecolor-like colors for a table_plain table (header on line 1).
# Brand colors for the agent glyphs (truecolor): Claude orange, OpenAI
# light gray, NixOS blue for nixbot; a sed filter.
paint_agents() {
  # UTF-8 bytes of U+EC82 (claude), U+EC81 (openai), U+F313 (nixos): no
  # dependence on the locale.
  local claude=$'\xee\xb2\x82' openai=$'\xee\xb2\x81' nixos=$'\xef\x8c\x93'
  local reset=$'\e[0m'
  sed \
    -e "s/${claude}/"$'\e[38;2;217;119;87m'"&${reset}/g" \
    -e "s/${openai}/"$'\e[38;2;200;200;200m'"&${reset}/g" \
    -e "s/${nixos}/"$'\e[38;2;126;186;228m'"&${reset}/g"
}

colorize() {
  local bold=$'\e[1m' bold_green=$'\e[1;32m' green=$'\e[32m'
  local yellow=$'\e[33m' red=$'\e[31m' bold_red=$'\e[1;31m'
  local cyan=$'\e[36m' reset=$'\e[0m'
  # EXPIRES under an hour: orange, under 30 minutes: bold red.
  local warn=$'\e[38;5;208m' urgent=$'\e[1;31m'
  sed -E \
    -e "1s/.*/${bold}&${reset}/" \
    -e "2,\$s/ (ACTIVE|READY) / ${bold_green}\1${reset} /" \
    -e "2,\$s/ (PENDING|QUEUED|BUILD|BUILDING|REBUILD|RESIZE|DELETING|BOOTING) / ${yellow}\1${reset} /" \
    -e "2,\$s/ (ERROR|FAILED|FAILURE) / ${bold_red}\1${reset} /" \
    -e "2,\$s/ (SHUTOFF|DELETED|expired) / ${red}\1${reset} /" \
    -e "2,\$s/ (grace [0-9]+[mhd]|draining) / ${yellow}\1${reset} /" \
    -e "2,\$s/ (busy) / ${green}\1${reset} /" \
    -e "2,\$s/ (([0-9]|[12][0-9])m)( +[0-9]+[mhd])/ ${urgent}\1${reset}\3/" \
    -e "2,\$s/ ([3-5][0-9]m)( +[0-9]+[mhd])/ ${warn}\1${reset}\2/" \
    -e "2,\$s/^([^ ]+)/${cyan}\1${reset}/" \
    | paint_agents
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
  jq -r '.[] | "\(.name)\t\(.kind)|\(.status)|\(.ip)|\(.owner)|\(.expires_at)|\(.grace_until)|\(.flavor)|\(.topic)|\(.pool_state)"'
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
    if out=$(remote_ls 2>&1)
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

    # Home, draw, clear the rest: no flicker. \e[K ends every line, or a
    # line shorter than the one drawn there before keeps its tail.
    printf '\e[H%s\e[J' "${frame//$'\n'/$'\e[K\n'}"

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
        case "${1:-}" in
          json)
            json=1
            ;;
          wide)
            WIDE=1
            ;;
          *)
            printf 'Output format must be json or wide\n' >&2
            show_help ls >&2
            return 2
            ;;
        esac
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
          show_help ls >&2
          return 2
        fi
        interval="$1"
        ;;
      *)
        printf 'Unknown option: %s\n' "$1" >&2
        show_help ls >&2
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
  out=$(remote_ls) || return 1
  if [[ -n "$json" || -n "$JSON" ]]
  then
    printf '%s\n' "$out"
    return 0
  fi
  render_table <<< "$out"
}

# "2026-11-04 14:13 (in 1h 59m)" for an epoch timestamp, "-" for 0.
fmt_time() {
  local at="$1" delta
  if [[ -z "$at" || "$at" == 0 || "$at" == null ]]
  then
    printf -- '-'
    return 0
  fi
  delta=$(( at - $(date +%s) ))
  if (( delta >= 0 ))
  then
    printf '%s (in %dh %dm)' "$(date -d "@$at" '+%F %H:%M')" \
      $(( delta / 3600 )) $(( delta % 3600 / 60 ))
  else
    delta=$(( -delta ))
    printf '%s (%dh %dm ago)' "$(date -d "@$at" '+%F %H:%M')" \
      $(( delta / 3600 )) $(( delta % 3600 / 60 ))
  fi
}

# One "Label:  value" line of inspect.
label() {
  printf '%s %s\n' "$(paint 1 "$(printf '%-14s' "$1:")")" "$2"
}

cmd_inspect() {
  local name="" boot="" info ip boot_meta="null"
  local -a opts=()
  while [[ -n "${1:-}" ]]
  do
    case "$1" in
      --boot)
        boot=1
        ;;
      -*)
        printf 'Unknown option: %s\n' "$1" >&2
        show_help inspect >&2
        return 2
        ;;
      *)
        name="$1"
        ;;
    esac
    shift
  done
  if [[ -z "$name" ]]
  then
    printf 'Missing worker name\n' >&2
    show_help inspect >&2
    return 2
  fi
  info=$(remote_ls | jq -c --arg n "$name" '.[] | select(.name == $n)') \
    || return 1
  if [[ -z "$info" ]]
  then
    printf 'No worker named %s\n' "$(paint_vm "$name")" >&2
    return 1
  fi
  if [[ -n "$boot" ]]
  then
    ip=$(worker_field "$name" ip) || return 1
    mapfile -t opts < <(ssh_opts "$name")
    boot_meta=$(ssh "${opts[@]}" -o ConnectTimeout=10 \
      "$(worker_field "$name" user)@${ip}" cat /run/rworker/metadata.json) \
      || return 1
  fi
  info=$(jq -c --argjson b "$boot_meta" \
    'if $b then . + {boot_metadata: $b} else . end' <<< "$info") || return 1
  if [[ -n "$JSON" ]]
  then
    jq . <<< "$info"
    return 0
  fi

  local -a f
  mapfile -t f < <(jq -r \
    --argjson icons "$( [[ -n "$ICONS" ]] && echo true || echo false )" "$JQ_AGENT"'
    .name, .kind, .status, (.owner // "-"), agent_label(.agent),
    (.agent_pid // "-"), (.agent_session // "-"), (.topic // "-"),
    (.cwd // "-"), (.flavor // "-"), (.ip // "-"), (.connected | tostring),
    (.created_at // "-"), (.expires_at // 0), (.grace_until // 0),
    (.last_active // 0), (.max_lifetime_end // 0), (.host_key // "-"),
    (.availability_zone // "-"), (.pool_state // ""),
    (.last_busy // 0)' <<< "$info")
  label Name "$(paint_vm "${f[0]}")"
  label Kind "${f[1]}"
  label Status "$(paint_state "${f[2]}")"
  label Owner "${f[3]}"
  printf '%s\n' "$(paint 1 Creator:)"
  local agent="${f[4]}"
  if [[ -n "$COLOR" ]]
  then
    agent=$(paint_agents <<< "$agent")
  fi
  label "  Agent" "${agent}$([[ "${f[5]}" != - ]] && printf ' (PID %s)' "${f[5]}")"
  label "  Session" "${f[6]}"
  label "  Topic" "${f[7]}"
  label "  Cwd" "${f[8]}"
  label Flavor "${f[9]}"
  label Zone "${f[18]}"
  label IP "${f[10]} (NetBird connected: ${f[11]})"
  label "Host key" "${f[17]}"
  label Created "${f[12]}"
  local expires left
  expires=$(fmt_time "${f[13]}")
  left=$(( ${f[13]%.*} - $(date +%s) ))
  if [[ "${f[13]}" == 0 ]]
  then
    :
  elif (( left < 1800 ))
  then
    # Expired or under 30 minutes: bold red; under an hour: orange.
    expires=$(paint '1;31' "$expires")
  elif (( left < 3600 ))
  then
    expires=$(paint '38;5;208' "$expires")
  fi
  label Expires "$expires"
  if [[ "${f[14]}" != 0 ]]
  then
    label Grace "until $(fmt_time "${f[14]}"); last in use $(fmt_time "${f[15]}")"
  fi
  if [[ -n "${f[19]}" ]]
  then
    # Pool workers have no TTL: the autoscaler drains them when idle.
    label "Pool state" "${f[19]} (last busy $(fmt_time "${f[20]}"))"
  else
    label "Max lifetime" "$(fmt_time "${f[16]}")"
  fi
  printf '%s\n' "$(paint 1 Metadata:)"
  jq -r '.metadata // {} | to_entries[] | select(.key != "host_key")
    | "  \(.key)=\(.value)"' <<< "$info"
  if [[ -n "$boot" ]]
  then
    printf '%s\n' "$(paint 1 'Boot metadata (/run/rworker/metadata.json):')"
    jq . <<< "$boot_meta" | sed 's/^/  /'
  fi
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
        show_help prune >&2
        return 2
        ;;
      *)
        names+=("$1")
        ;;
    esac
    shift
  done

  me="${USER}@$(hostname)"
  info=$(remote_ls) || return 1
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
      [[ -n "$JSON" ]] || ok "deleted $(paint_vm "$name")"
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
      --ttl|--flavor|--disk|--profile)
        if [[ -z "${2:-}" ]]
        then
          printf '%s needs a value\n' "$1" >&2
          return 2
        fi
        up_args+=("$1" "$2")
        shift
        ;;
      --scratch|--nix-cache|--no-nix-cache)
        up_args+=("$1")
        ;;
      --topic)
        up_args+=("$1" "${2:-}")
        shift
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
        show_help exec >&2
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
    printf 'Missing command\n' >&2
    show_help exec >&2
    return 2
  fi

  local json="$JSON" info name ip
  info=$(JSON=1 cmd_up --quiet-topic-warning "${up_args[@]}") || return 1
  name=$(jq -er .name <<< "$info") || return 1
  ip=$(jq -er .ip <<< "$info") || return 1
  printf '%s %s is %s\n' "$(paint 32 '✔')" "$(paint_vm "$name")" "$(paint '1;32' 'READY')" >&2

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
    printf 'Command failed (%d); keeping %s: %s ssh %s\n' "$rc" "$(paint_vm "$name")" \
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
  ok "$(paint_vm "$name") now expires $(fmt_expiry "$(jq -r .expires_at <<< "$out")"), at most until $(date -d "@$(jq -r .max_lifetime_end <<< "$out")" '+%a %H:%M')"
}

cmd_down() {
  if [[ -z "${1:-}" ]]
  then
    show_help down >&2
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
    ok "deleted $(paint_vm "$1")"
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

# Run the shared job manager on the worker through the pinned SSH connection.
cmd_jobs_remote() {
  local action="$1" worker="${2:-}" arg remote="bash -s --"
  shift 2 || return 2
  if [[ "$action" == logs ]]
  then
    set -- "$@" --worker-prefix "$worker"
  fi
  if [[ -z "$worker" ]]
  then
    printf 'worker name required\n' >&2
    return 2
  fi
  for arg in "$action" "$@"
  do
    printf -v arg '%q' "$arg"
    remote+=" $arg"
  done
  cmd_ssh "$worker" "$remote" <<'REMOTE_JOBS'
set -eu
umask 077
root="$HOME/.local/state/rworker/jobs"
mkdir -p "$root"
action=$1
shift
valid() { [[ "$1" =~ ^[a-zA-Z0-9][a-zA-Z0-9_.-]*$ ]]; }
case "$action" in
  start)
    label=""
    workdir="$HOME"
    while [[ $# -gt 0 ]]
    do
      case "$1" in
        --name) label=$2; shift 2 ;;
        --workdir) workdir=$2; shift 2 ;;
        --) shift; break ;;
        *) printf 'unknown option: %s\n' "$1" >&2; exit 2 ;;
      esac
    done
    [[ $# -eq 1 ]] || { printf 'provide one command after --\n' >&2; exit 2; }
    if [[ -n "$label" ]]
    then
      valid "$label" || { printf 'invalid job name\n' >&2; exit 2; }
      dir="$root/$label"
      mkdir "$dir" || exit 1
    else
      dir=$(mktemp -d "$root/job-XXXXXXXX")
    fi
    printf '%s\n' "$1" > "$dir/command"
    printf '%s\n' "$workdir" > "$dir/workdir"
    date -u +%FT%TZ > "$dir/started"
    cat > "$dir/run" <<'RUN_JOB'
#!/usr/bin/env bash
job_dir=$1
cd "$(cat "$job_dir/workdir")" || { printf '%s\n' 1 > "$job_dir/exit"; exit 1; }
bash "$job_dir/command"
status=$?
rm -f "$job_dir/command"
printf '%s\n' "$status" > "$job_dir/exit"
exit "$status"
RUN_JOB
    nohup bash "$dir/run" "$dir" </dev/null >"$dir/log" 2>&1 &
    printf '%s\n' "$!" > "$dir/pid"
    basename "$dir"
    ;;
  register)
    [[ $# -eq 3 && "$2" == --log ]] || { printf 'usage: register JOB --log PATH\n' >&2; exit 2; }
    valid "$1" || { printf 'invalid job name\n' >&2; exit 2; }
    [[ "$3" == /* && -f "$3" ]] || { printf 'log must be an existing absolute file path\n' >&2; exit 2; }
    mkdir "$root/$1"
    printf '%s\n' "$3" > "$root/$1/log-path"
    date -u +%FT%TZ > "$root/$1/started"
    ;;
  jobs)
    for dir in "$root"/*
    do
      [[ -d "$dir" ]] || continue
      state=registered
      if [[ -f "$dir/exit" ]]
      then
        state="exit $(cat "$dir/exit")"
      elif [[ -f "$dir/pid" ]]
      then
        if kill -0 "$(cat "$dir/pid")" 2>/dev/null
        then
          state=running
        else
          state=unknown
        fi
      fi
      printf '%s\t%s\t%s\n' "${dir##*/}" "$state" "$(cat "$dir/started")"
    done
    ;;
  ps)
    processes=$(ps -eo pid=,ppid=,etime=,comm=)
    for dir in "$root"/*
    do
      [[ -d "$dir" && -f "$dir/pid" && ! -f "$dir/exit" ]] || continue
      pid=$(cat "$dir/pid")
      [[ "$pid" =~ ^[0-9]+$ ]] || continue
      awk -v root="$pid" -v job="${dir##*/}" '
        { pids[NR]=$1; parents[NR]=$2; elapsed[NR]=$3; command[NR]=$4 }
        END {
          selected[root]=1
          do {
            changed=0
            for (i=1; i<=NR; i++)
              if (selected[parents[i]] && !selected[pids[i]]) {
                selected[pids[i]]=1
                changed=1
              }
          } while (changed)
          for (i=1; i<=NR; i++)
            if (selected[pids[i]])
              printf "%s\t%s\t%s\t%s\t%s\n", job, pids[i], parents[i], elapsed[i], command[i]
        }
      ' <<< "$processes"
    done
    ;;
  logs)
    job=""
    lines=200
    follow=""
    worker_prefix=""
    while [[ $# -gt 0 ]]
    do
      case "$1" in
        --lines) lines=$2; shift 2 ;;
        --follow|-f) follow=1; shift ;;
        --worker-prefix) worker_prefix=$2; shift 2 ;;
        *) [[ -z "$job" ]] || exit 2; job=$1; shift ;;
      esac
    done
    [[ "$lines" =~ ^[0-9]+$ ]] || { printf 'invalid line count\n' >&2; exit 2; }
    if [[ -n "$job" ]]
    then
      valid "$job" || exit 2
      dirs=("$root/$job")
    else
      dirs=("$root"/*)
    fi
    if [[ -n "$follow" ]]
    then
      colors=(31 32 33 34 35 36)
      pids=()
      if [[ -n "$job" ]]
      then
        dir="${dirs[0]}"
        [[ -d "$dir" ]] || { printf 'unknown job\n' >&2; exit 1; }
        logfile="$dir/log"
        [[ ! -f "$dir/log-path" ]] || logfile=$(cat "$dir/log-path")
        name=${dir##*/}
        color=${colors[0]}
        tail -n "$lines" -f -- "$logfile" | while IFS= read -r line || [[ -n "$line" ]]
        do
          printf '\033[1;%sm%s/%s\033[0m %s\n' "$color" "$worker_prefix" "$name" "$line"
        done &
        pids+=("$!")
        wait "${pids[@]}"
        exit $?
      fi

      declare -A followed=()
      index=0
      reported_waiting=""
      cleanup_tailers() {
        local pid
        for pid in "${pids[@]}"
        do
          kill "$pid" 2>/dev/null || true
        done
      }
      trap cleanup_tailers EXIT
      trap 'exit 130' INT
      trap 'exit 143' TERM
      while :
      do
        found_job=""
        for dir in "$root"/*
        do
          [[ -d "$dir" ]] || continue
          name=${dir##*/}
          [[ -n "${followed[$name]:-}" ]] && continue
          logfile="$dir/log"
          if [[ -f "$dir/log-path" ]]
          then
            logfile=$(cat "$dir/log-path")
          fi
          [[ -f "$logfile" ]] || continue
          followed["$name"]=1
          found_job=1
          color=${colors[$((index % ${#colors[@]}))]}
          tail -n "$lines" -f -- "$logfile" | while IFS= read -r line || [[ -n "$line" ]]
          do
            printf '\033[1;%sm%s/%s\033[0m %s\n' "$color" "$worker_prefix" "$name" "$line"
          done &
          pids+=("$!")
          ((index += 1))
        done
        if [[ -z "$found_job" && ${#followed[@]} -eq 0 && -z "$reported_waiting" ]]
        then
          printf 'waiting for jobs...\n' >&2
          reported_waiting=1
        fi
        sleep 1
      done
    fi
    for dir in "${dirs[@]}"
    do
      [[ -d "$dir" ]] || { [[ -z "$job" ]] && continue; printf 'unknown job\n' >&2; exit 1; }
      logfile="$dir/log"
      [[ ! -f "$dir/log-path" ]] || logfile=$(cat "$dir/log-path")
      printf '==> %s/%s <==\n' "$worker_prefix" "${dir##*/}"
      tail -n "$lines" -- "$logfile"
    done
    ;;
esac
REMOTE_JOBS
}

cmd_logs() {
  local lines=200 follow="" no_events="" arg
  if [[ -n "${1:-}" && "$1" != -* ]]
  then
    cmd_jobs_remote logs "$@"
    return
  fi
  while [[ -n "${1:-}" ]]
  do
    case "$1" in
      --lines)
        lines="${2:-}"
        shift 2
        ;;
      --follow|-f)
        follow=1
        shift
        ;;
      --no-events)
        no_events=1
        shift
        ;;
      *)
        printf 'Unknown logs option: %s\n' "$1" >&2
        action_help logs >&2
        return 2
        ;;
    esac
  done
  if [[ ! "$lines" =~ ^[0-9]+$ ]]
  then
    printf 'invalid line count\n' >&2
    return 2
  fi
  if [[ -n "$follow" ]]
  then
    cmd_logs_all_follow "$lines" "$no_events"
  else
    cmd_logs_all "$lines"
  fi
}

cmd_ps() {
  local workers worker target kind login processes line rows status=0
  if (( $# > 1 )) || [[ "${1:-}" == -* ]]
  then
    action_help ps >&2
    return 2
  fi
  workers=$(remote_ls) || return 1
  if [[ -n "${1:-}" ]]
  then
    target="$1"
    workers=$(jq -r --arg n "${target#*@}" '.[] | select(.name == $n) | [.name, .kind] | @tsv' <<< "$workers") || return 1
    if [[ -z "$workers" ]]
    then
      printf 'No worker named %s\n' "$target" >&2
      return 1
    fi
  else
    workers=$(jq -r '.[] | [.name, .kind] | @tsv' <<< "$workers") || return 1
  fi
  rows=$'WORKER\tJOB\tPID\tPPID\tELAPSED\tCOMMAND'
  while IFS=$'\t' read -r worker kind
  do
    [[ -n "$worker" ]] || continue
    if [[ "${target:-}" == *@* ]]
    then
      login="$target"
    elif [[ "$kind" == adhoc ]]
    then
      login="agent@$worker"
    else
      login="$worker"
    fi
    if ! processes=$(cmd_jobs_remote ps "$login")
    then
      printf 'could not read job processes from %s\n' "$worker" >&2
      status=1
      continue
    fi
    while IFS= read -r line
    do
      [[ -n "$line" ]] || continue
      rows+=$'\n'"$worker"$'\t'"$line"
    done <<< "$processes"
  done <<< "$workers"
  rows=$(column -t -s $'\t' <<< "$rows") || return 1
  if [[ -n "$COLOR" ]]
  then
    local bold=$'\e[1m' cyan=$'\e[36m' green=$'\e[32m' yellow=$'\e[33m' reset=$'\e[0m'
    sed -E \
      -e "1s/.*/${bold}&${reset}/" \
      -e "2,\$s/^([^ ]+)( +)([^ ]+)/${cyan}\\1${reset}\\2${green}\\3${reset}/" \
      -e "2,\$s/([^ ]+)\$/${yellow}\\1${reset}/" <<< "$rows"
  else
    printf '%s\n' "$rows"
  fi
  return "$status"
}

cmd_logs_all() {
  local lines="$1" workers worker status=0
  workers=$(remote_ls) || return 1
  while IFS= read -r worker
  do
    [[ -n "$worker" ]] || continue
    cmd_jobs_remote logs "$worker" --lines "$lines" || {
      printf 'could not read logs from %s\n' "$(paint_vm "$worker")" >&2
      status=1
    }
  done < <(jq -r '.[].name' <<< "$workers")
  return "$status"
}

cmd_logs_all_follow() {
  local lines="$1" no_events="${2:-}" workers worker pid ready_workers events_pid=""
  local discovery_interval=5
  declare -A pids=() current=()
  cleanup_followers() {
    for worker in "${!pids[@]}"
    do
      kill "${pids[$worker]}" 2>/dev/null || true
    done
    if [[ -n "$events_pid" ]]
    then
      kill "$events_pid" 2>/dev/null || true
      wait "$events_pid" 2>/dev/null || true
    fi
  }
  trap cleanup_followers EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  if [[ -z "$no_events" ]]
  then
    cmd_events --interval "$discovery_interval" &
    events_pid=$!
  fi
  while :
  do
    if ! workers=$(remote_ls)
    then
      printf 'could not refresh worker list; retrying\n' >&2
      sleep "$discovery_interval"
      continue
    fi
    current=()
    ready_workers=$(jq -r '.[] | select((.ip // "") != "" and (.host_key // "") != "") | .name' <<< "$workers")
    while IFS= read -r worker
    do
      [[ -n "$worker" ]] || continue
      current["$worker"]=1
    done < <(jq -r '.[].name' <<< "$workers")
    while IFS= read -r worker
    do
      [[ -n "$worker" ]] || continue
      if [[ -n "${pids[$worker]:-}" ]] && kill -0 "${pids[$worker]}" 2>/dev/null
      then
        continue
      fi
      unset 'pids[$worker]'
      cmd_jobs_remote logs "$worker" --lines "$lines" --follow &
      pids["$worker"]=$!
    done <<< "$ready_workers"
    for worker in "${!pids[@]}"
    do
      if [[ -z "${current[$worker]:-}" ]]
      then
        pid=${pids[$worker]}
        kill "$pid" 2>/dev/null || true
        unset 'pids[$worker]'
      fi
    done
    sleep "$discovery_interval"
  done
}

emit_event() {
  local kind="$1" target="$2" details="${3:-}" color
  case "$kind" in
    *-added)
      color=32
      ;;
    *-deleted)
      color=31
      ;;
    job-state)
      color=33
      ;;
    *)
      color=36
      ;;
  esac
  printf '%s %s %s' "$(date -u +%FT%TZ)" "$(paint "$color" "$kind")" "$(paint_event_target "$target")"
  if [[ -n "$details" ]]
  then
    printf ' %s' "$(paint 33 "$details")"
  fi
  printf '\n'
}

cmd_events() {
  local interval=2 workers worker ready_workers jobs job state started key previous initialized=""
  local -A previous_workers=() current_workers=() previous_jobs=() current_jobs=() polled_workers=()
  while [[ -n "${1:-}" ]]
  do
    case "$1" in
      --interval)
        interval="${2:-}"
        shift 2
        ;;
      *)
        printf 'Unknown events option: %s\n' "$1" >&2
        action_help events >&2
        return 2
        ;;
    esac
  done
  if [[ ! "$interval" =~ ^[0-9]+$ ]] || (( interval < 1 ))
  then
    printf 'interval must be a positive whole number of seconds\n' >&2
    return 2
  fi
  while :
  do
    if ! workers=$(remote_ls)
    then
      printf 'could not refresh worker list; retrying\n' >&2
      sleep "$interval"
      continue
    fi
    current_workers=()
    current_jobs=()
    polled_workers=()
    while IFS= read -r worker
    do
      [[ -n "$worker" ]] || continue
      current_workers["$worker"]=1
      if [[ -n "$initialized" && -z "${previous_workers[$worker]:-}" ]]
      then
        emit_event worker-added "$worker"
      fi
    done < <(jq -r '.[].name' <<< "$workers")
    if [[ -n "$initialized" ]]
    then
      for worker in "${!previous_workers[@]}"
      do
        if [[ -z "${current_workers[$worker]:-}" ]]
        then
          emit_event worker-deleted "$worker"
        fi
      done
    fi
    ready_workers=$(jq -r '.[] | select((.ip // "") != "" and (.host_key // "") != "") | .name' <<< "$workers")
    while IFS= read -r worker
    do
      [[ -n "$worker" ]] || continue
      if ! jobs=$(cmd_jobs_remote jobs "$worker")
      then
        continue
      fi
      polled_workers["$worker"]=1
      while IFS=$'\t' read -r job state started
      do
        [[ -n "$job" ]] || continue
        key="$worker/$job"
        current_jobs["$key"]="$state"
        previous="${previous_jobs[$key]:-}"
        if [[ -n "$initialized" && -z "$previous" ]]
        then
          emit_event job-added "$key" "state=$state"
        elif [[ -n "$initialized" && "$state" != "$previous" ]]
        then
          emit_event job-state "$key" "$previous -> $state"
        fi
      done <<< "$jobs"
    done <<< "$ready_workers"
    if [[ -n "$initialized" ]]
    then
      for key in "${!previous_jobs[@]}"
      do
        worker="${key%%/*}"
        if [[ -z "${current_workers[$worker]:-}" ]]
        then
          continue
        fi
        if [[ -z "${polled_workers[$worker]:-}" ]]
        then
          current_jobs["$key"]="${previous_jobs[$key]}"
        elif [[ -z "${current_jobs[$key]:-}" ]]
        then
          emit_event job-deleted "$key"
        fi
      done
    fi
    previous_workers=()
    for worker in "${!current_workers[@]}"
    do
      previous_workers["$worker"]=1
    done
    previous_jobs=()
    for key in "${!current_jobs[@]}"
    do
      previous_jobs["$key"]="${current_jobs[$key]}"
    done
    initialized=1
    sleep "$interval"
  done
}

cmd_ssh() {
  local name ip user opts login_user=""
  # -l USER (like ssh's), before the name.
  if [[ "${1:-}" == -l ]]
  then
    login_user="${2:-}"
    if [[ -z "$login_user" ]]
    then
      printf -- '-l needs a user\n' >&2
      show_help ssh >&2
      return 2
    fi
    shift 2
  fi
  if [[ -z "${1:-}" ]]
  then
    show_help ssh >&2
    return 2
  fi
  split_target "$1" || return 2
  shift
  name="$TARGET_NAME"
  if [[ -n "$login_user" ]]
  then
    TARGET_USER="$login_user"
  fi
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
    show_help sync >&2
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
    ok "synced $src to $(paint_vm "$name"):$dest"
  fi
}

cmd_cp() {
  local src="${1:-}" dst="${2:-}" remote local_path direction target ip user opts
  if [[ -z "$src" || -z "$dst" || -n "${3:-}" ]]
  then
    show_help cp >&2
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
    show_help cp >&2
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

# The s3:// substituters, the AWS profiles they name and the trusted public
# keys of this host's Nix, as JSON. Only these leave the host: nix.conf can
# hold access-tokens and netrc paths, and non-S3 caches (a LAN mirror) are
# not reachable from OpenStack anyway.
nix_cache_settings() {
  local cfg
  if ! cfg=$(nix config show --json 2>/dev/null)
  then
    printf 'Could not read the Nix configuration (nix config show)\n' >&2
    return 1
  fi
  jq -c '
    def vals($k): (.[$k].value // []);
    ((vals("substituters") + vals("extra-substituters"))
      | map(select(startswith("s3://"))) | unique) as $subs
    | {substituters: $subs,
       profiles: ($subs | map(capture("[?&]profile=(?<p>[^&]+)").p // "default")
                  | unique),
       keys: ((vals("trusted-public-keys") + vals("extra-trusted-public-keys"))
              | unique)}' <<< "$cfg"
}

# One profile section ("[name]" and its lines) of an AWS credentials file.
aws_profile_section() {
  awk -v want="[$2]" '
    $0 == want { found = 1; print; next }
    /^\[/      { found = 0 }
    found      { print }' "$1"
}

# Let a worker substitute from this host's S3 cache. Prints one JSON object
# on stdout, progress on stderr. See `help nix-cache`.
push_nix_cache() {
  local name="$1" dry="${2:-}" settings creds_file profile section creds="" conf
  local ip opts i url before after state="timeout" verified=false
  settings=$(nix_cache_settings) || return 1
  if [[ $(jq '.substituters | length' <<< "$settings") == 0 ]]
  then
    printf 'This host'"'"'s Nix has no s3:// substituter; nothing to push\n' >&2
    return 1
  fi
  creds_file="${AWS_SHARED_CREDENTIALS_FILE:-$HOME/.aws/credentials}"
  while read -r profile
  do
    section=$(aws_profile_section "$creds_file" "$profile" 2>/dev/null)
    if [[ -z "$section" ]]
    then
      printf 'No [%s] profile in %s (named by an s3:// substituter)\n' \
        "$profile" "$creds_file" >&2
      return 1
    fi
    creds+="${section}"$'\n'
  done < <(jq -r '.profiles[]' <<< "$settings")
  conf=$(jq -r --arg from "$(hostname)" --arg at "$(date -u +%FT%TZ)" '
    "# Pushed by rworker nix-cache from \($from) at \($at).",
    "extra-substituters = \(.substituters | join(" "))",
    "extra-trusted-public-keys = \(.keys | join(" "))"' <<< "$settings")
  if [[ -n "$dry" ]]
  then
    jq -c --arg n "$name" '. + {name: $n, dry_run: true}' <<< "$settings"
    return 0
  fi

  ip=$(worker_field "$name" ip) || return 1
  mapfile -t opts < <(ssh_opts "$name")
  # NetBird may still be setting up the route to a fresh worker.
  for i in $(seq 1 10)
  do
    if ssh "${opts[@]}" -o ConnectTimeout=5 "agent@${ip}" true 2>/dev/null
    then
      break
    fi
    sleep 3
  done
  # An image without this feature has no /run/rworker-nix (agent cannot
  # create it); say so instead of failing on a shell error.
  if ! ssh "${opts[@]}" "agent@${ip}" 'test -d /run/rworker-nix' 2>/dev/null
  then
    jq -c --arg n "$name" \
      '{ok: false, name: $n, daemon: "image-too-old", reachable: false,
        substituters, profiles}' <<< "$settings"
    return 0
  fi
  before=$(ssh "${opts[@]}" "agent@${ip}" \
    'systemctl show -p ExecMainStartTimestampMonotonic --value rworker-nix-config.service' \
    2>/dev/null)
  # Credentials first, nix.conf last: replacing nix.conf is what restarts the
  # daemon (path unit on the worker). The secret travels on stdin only.
  # shellcheck disable=SC2016 # runs on the worker
  printf '%s' "$creds" | ssh "${opts[@]}" "agent@${ip}" \
    'umask 077; cat > /run/rworker-nix/aws-credentials.new && mv /run/rworker-nix/aws-credentials.new /run/rworker-nix/aws-credentials' \
    || return 1
  # shellcheck disable=SC2016
  printf '%s\n' "$conf" | ssh "${opts[@]}" "agent@${ip}" \
    'umask 077; cat > /run/rworker-nix/nix.conf.new && mv /run/rworker-nix/nix.conf.new /run/rworker-nix/nix.conf' \
    || return 1

  # Does the worker reach the bucket with what it was given?
  url=$(jq -r '.substituters[0]' <<< "$settings")
  # shellcheck disable=SC2029 # the URL is quoted here, on purpose
  if ssh "${opts[@]}" "agent@${ip}" \
    "AWS_SHARED_CREDENTIALS_FILE=/run/rworker-nix/aws-credentials timeout 60 nix store info --store $(printf '%q' "$url")" \
    > /dev/null 2> "${STATE_DIR}/.nix-cache.err"
  then
    verified=true
  else
    printf 'The worker cannot reach the S3 cache: %s\n' \
      "$(tail -n 3 "${STATE_DIR}/.nix-cache.err")" >&2
  fi
  rm -f "${STATE_DIR}/.nix-cache.err"

  # Did its nix-daemon pick the settings up (restarted by the path unit)?
  if [[ $(ssh "${opts[@]}" "agent@${ip}" \
      'systemctl show -p LoadState --value rworker-nix-config.service' 2>/dev/null) \
    != loaded ]]
  then
    state="image-too-old"
  else
    for i in $(seq 1 20)
    do
      after=$(ssh "${opts[@]}" "agent@${ip}" \
        'systemctl show -p ExecMainStartTimestampMonotonic --value rworker-nix-config.service; systemctl is-active nix-daemon.socket' \
        2>/dev/null | paste -sd' ')
      if [[ "${after%% *}" != "$before" && "$after" == *" active" ]]
      then
        state="restarted"
        break
      fi
      sleep 1
    done
  fi
  jq -c --arg n "$name" --arg s "$state" --argjson v "$verified" \
    '{ok: ($v and $s == "restarted"), name: $n, daemon: $s,
      reachable: $v, substituters, profiles}' <<< "$settings"
}

cmd_nix_cache() {
  local name="" dry="" out
  while [[ -n "${1:-}" ]]
  do
    case "$1" in
      --dry-run|-n)
        dry=1
        ;;
      -*)
        printf 'Unknown option: %s\n' "$1" >&2
        show_help nix-cache >&2
        return 2
        ;;
      *)
        name="$1"
        ;;
    esac
    shift
  done
  if [[ -z "$name" ]]
  then
    show_help nix-cache >&2
    return 2
  fi
  out=$(push_nix_cache "$name" "$dry") || return 1
  if [[ -n "$JSON" ]]
  then
    printf '%s\n' "$out"
    return 0
  fi
  if [[ -n "$dry" ]]
  then
    printf 'Would push to %s:\n' "$(paint_vm "$name")"
    jq -r '"  substituter \(.substituters[])", "  profile     \(.profiles[])",
           "  trusted keys \(.keys | length)"' <<< "$out"
    return 0
  fi
  case "$(jq -r .daemon <<< "$out")" in
    restarted)
      ok "$(paint_vm "$name") substitutes from the S3 cache"
      ;;
    image-too-old)
      printf '%s %s runs an image from before --nix-cache existed: nothing was pushed (create a new worker)\n' \
        "$(paint 33 '!')" "$(paint_vm "$name")" >&2
      return 1
      ;;
    *)
      printf '%s pushed to %s, but its nix-daemon did not restart in time\n' \
        "$(paint 33 '!')" "$(paint_vm "$name")" >&2
      ;;
  esac
}

cmd_builder() {
  local name="${1:-}" ip key
  if [[ -z "$name" ]]
  then
    show_help builder >&2
    return 2
  fi
  ip=$(worker_field "$name" ip) || return 1
  key=$(worker_field "$name" host_key | base64 -w0) || return 1
  # The Nix daemon opens builder connections as root, without the user's SSH
  # agent or config, so the line names the private half of the key that `up`
  # handed to the worker ("-" would make root try its own default key).
  local identity="${RWORKER_KEY:-$HOME/.ssh/id_ed25519.pub}"
  identity="${identity%.pub}"
  [[ -r "$identity" ]] || identity="-"
  local line
  line=$(printf 'ssh-ng://agent@%s x86_64-linux %s 16 1 nixos-test,benchmark,big-parallel,kvm - %s' \
    "$ip" "$identity" "$key")
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
    __workers)
      cmd_workers "${2:-}"
      return 0
      ;;
    -h|--help|help)
      if [[ -n "${2:-}" ]]
      then
        action_help "$2" | paint_help
      else
        usage | paint_help overview
      fi
      return 0
      ;;
    "")
      # The overview, colored like --help when stderr is a terminal.
      usage | paint_help overview >&2
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
      action_help "$action" | paint_help
      return 0
    fi
  done
  case "$action" in
    start)
      cmd_jobs_remote "$action" "$@"
      ;;
    jobs)
      cmd_jobs_remote "$action" "$@"
      ;;
    ps)
      cmd_ps "$@"
      ;;
    logs)
      cmd_logs "$@"
      ;;
    events)
      cmd_events "$@"
      ;;
    register)
      cmd_jobs_remote "$action" "$@"
      ;;

    up)
      cmd_up "$@"
      ;;
    profiles)
      if [[ $# -ne 0 ]]
      then
        action_help profiles >&2
        return 2
      fi
      local profiles
      profiles=$(remote profiles) || return 1
      profiles=$(jq 'sort_by([(.default | not), .name])' <<< "$profiles") || return 1
      if [[ -n "$JSON" ]]
      then
        printf '%s\n' "$profiles"
      else
        local rows
        rows=$(jq -r '(["PROFILE", "FLAVOR", "DISK (GiB)", "IMAGE TAGS"], (.[] | [(.name + (if .default then "*" else "" end)), .flavor, (.disk | tostring), (.image_tags | join(", "))])) | @tsv' <<< "$profiles" | column -t -s $'\t') || return 1
        if [[ -n "$COLOR" ]]
        then
          colorize <<< "$rows"
        else
          printf '%s\n' "$rows"
        fi
      fi
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
    nix-cache)
      cmd_nix_cache "$@"
      ;;
    inspect)
      cmd_inspect "$@"
      ;;
    cp)
      cmd_cp "$@"
      ;;
    *)
      printf 'Unknown action: %s\n' "$action" >&2
      show_help >&2
      return 2
      ;;
  esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
  main "$@"
fi

# vim: set ft=sh et ts=2 sw=2 :
