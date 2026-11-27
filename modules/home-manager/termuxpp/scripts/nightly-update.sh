usage() {
  printf 'Usage: %s [--check]\n' "$(basename "$0")"
}

log() {
  printf '%s %s\n' "$(date -Iseconds)" "$*"
}

finish() {
  local status="$?"
  if (( status != 0 ))
  then
    nightly_result=failed
  fi
  if (( wake_locked ))
  then
    timeout 15 tpp wake-lock release >/dev/null 2>&1 || :
  fi
  log "Result: $nightly_result (exit $status)"
  printf 'TermuxPP nightly update: %s (exit %s)%s\n' "$nightly_result" "$status" \
    "${killed_run:+; the previous run was killed}" >&3
}

run_step() {
  local step="$1" limit="$2" status=0
  shift 2
  log "Starting $step"
  timeout --kill-after=15 "$limit" "$@" </dev/null || status=$?
  log "Finished $step (exit $status)"
  return "$status"
}

# Build the current main on a native ARM runner that nixpp leases through the
# rworker controller (the `lease` section of /etc/nixpp/upgrade.json; the
# worker evaluates, builds and is released afterwards) and switch to it. There
# is deliberately no fallback to an older system: the result is the latest main
# or no change. A queued runner or a lost connection fails one attempt, so
# retry within the 3600 s the Tasker action waits.
upgrade_profile() {
  local attempt=1 deadline=$((SECONDS + 3000)) limit
  while :
  do
    limit=$((deadline - SECONDS))
    if (( limit < 600 ))
    then
      log 'Not enough time left for another rworker upgrade attempt.'
      return 1
    fi
    (( limit <= 2400 )) || limit=2400
    run_step "profile-$attempt" "$limit" nixpp upgrade --rworker && return 0
    log "rworker upgrade attempt $attempt failed."
    attempt=$((attempt + 1))
    sleep 60
  done
}

# Readiness of the lease route without leasing anything: log in to the
# controller's restricted account with the phone's key, pinned host key and all.
# Its gate refuses an unknown request with "refused: invalid action" only after
# it has accepted the key, so that answer proves the route.
check_lease() {
  local config=/etc/nixpp/upgrade.json controller host_key key destination port host entry known_hosts reply
  if ! controller=$(jq -er '.lease.controller' "$config") ||
    ! host_key=$(jq -er '.lease.controller_host_key' "$config")
  then
    log "No lease settings in $config."
    return 1
  fi
  key=$(jq -r '.lease.key // empty' "$config")
  key=${key:-$HOME/.ssh/id_ed25519}
  if [[ ! -r "$key" ]]
  then
    log "The phone's SSH key $key is missing."
    return 1
  fi
  destination=$controller
  port=22
  if [[ "$destination" == *:* ]]
  then
    port=${destination##*:}
    destination=${destination%:*}
  fi
  host=${destination##*@}
  entry=$host
  if [[ "$port" != 22 ]]
  then
    entry="[$host]:$port"
  fi
  known_hosts=$(mktemp) || return 1
  printf '%s %s\n' "$entry" "$host_key" >"$known_hosts"
  reply=$(timeout 60 ssh -F /dev/null -o BatchMode=yes -o ConnectTimeout=30 \
    -o StrictHostKeyChecking=yes -o UserKnownHostsFile="$known_hosts" \
    -o IdentitiesOnly=yes -i "$key" -p "$port" -- "$destination" \
    'rworker check' </dev/null 2>&1) || true
  rm -f -- "$known_hosts"
  if [[ "$reply" != *'refused: invalid action'* ]]
  then
    log "The rworker controller did not accept the phone's key: ${reply:-no answer}"
    return 1
  fi
  log 'The rworker controller accepts the phone.'
}

maintenance() {
  local config failed=0
  upgrade_profile || return 1
  run_step gc 1200 nixpp gc --keep-generations 3 || failed=1
  run_step dotfiles 180 yadm pull --ff-only || failed=1

  if [[ -s "${XDG_DATA_HOME:-$HOME/.local/share}/atuin/session" ]]
  then
    run_step atuin 90 atuin sync || failed=1
  else
    log 'Atuin is signed out. Skipping sync.'
  fi

  for config in private work
  do
    local manifest="${XDG_CONFIG_HOME:-$HOME/.config}/mani/$config.yaml" remote_host
    remote_host=$(manifest_host "$manifest")
    if [[ ! -f "$manifest" ]]
    then
      log "No $config mani config. Skipping."
    elif [[ -n "$remote_host" ]] && ! host_reachable "$remote_host"
    then
      # Work remotes are only reachable from the work network or VPN; an
      # unreachable host is not a failure of the night.
      log "$remote_host is unreachable. Skipping the $config repositories."
    elif run_step "mani-$config-sync" 240 mani --config "$manifest" sync
    then
      run_step "mani-$config-update" 480 mani --config "$manifest" run update --all --ignore-non-existing || failed=1
    else
      failed=1
    fi
  done
  return "$failed"
}

# The host of the first remote a mani manifest clones from (https, ssh:// or
# scp-like git@host:path URLs), or nothing.
manifest_host() {
  [[ -f "$1" ]] || return 0
  sed -nE 's#^[[:space:]]*url:[[:space:]]*["'"'"']?([a-z+]+://)?([^@/]*@)?([^/:"'"'"']+).*#\3#p' "$1" | head -n 1
}

# Whether a TCP connection to HOST (HTTPS, else SSH) succeeds within seconds.
host_reachable() {
  local port
  for port in 443 22
  do
    # shellcheck disable=SC2016 # host and port are arguments of the inner shell
    if timeout 10 bash -c 'exec 3<>"/dev/tcp/$1/$2"' _ "$1" "$port" 2>/dev/null
    then
      return 0
    fi
  done
  return 1
}

main() {
  local mode=update state_dir log_file free_kib killed_at=''
  nightly_result=failed
  killed_run=''
  wake_locked=0
  if (( $# > 1 ))
  then
    usage >&2
    return 2
  fi
  case "${1:-}" in
    '') ;;
    --check) mode=check ;;
    --help|-h)
      usage
      return 0
      ;;
    *)
      usage >&2
      return 2
      ;;
  esac

  umask 077
  export GIT_TERMINAL_PROMPT=0 SSH_ASKPASS_REQUIRE=never NO_COLOR=1
  export GIT_SSH_COMMAND='ssh -o BatchMode=yes -o ConnectTimeout=15 -o ServerAliveInterval=15 -o ServerAliveCountMax=2'
  state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/termuxpp-nightly"
  log_file="$state_dir/last-run.log"
  mkdir -p -- "$state_dir" || return 1
  exec 9>"$state_dir/run.lock"
  if ! flock -n 9
  then
    printf 'TermuxPP nightly update is already running.\n'
    return 0
  fi
  if [[ -f "$log_file" ]]
  then
    # Every run ends with a Result line from its EXIT trap. A log without
    # one belongs to a run that was killed outright (SIGKILL, for example
    # Android's memory limiter taking down the app with its children). Keep
    # that log until the next killed run, so later runs do not rotate it away.
    if ! grep -q '^[^ ]* Result: ' "$log_file"
    then
      killed_run="$(head -n 1 -- "$log_file" | cut -d ' ' -f 1)"
      killed_run=${killed_run:-unknown}
      killed_at="$(date -r "$log_file" -Iseconds)"
      cp -f -- "$log_file" "$state_dir/killed-run.log" || return 1
    fi
    mv -f -- "$log_file" "$state_dir/previous-run.log" || return 1
  fi
  exec 3>&1 >>"$log_file" 2>&1
  trap 'finish' EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM HUP
  cd "$HOME" || return 1
  log "Starting nightly maintenance ($mode)"
  if [[ -n "$killed_run" ]]
  then
    log "The previous run (started $killed_run, last output $killed_at) ended without a result: it was killed. Its log is $state_dir/killed-run.log."
  fi

  plugged=$(timeout 15 tpp battery plugged </dev/null) || plugged=''
  if [[ -z "$plugged" || "$plugged" == UNPLUGGED ]]
  then
    nightly_result='deferred (not charging or battery status unavailable)'
    return 0
  fi
  if ! timeout 15 tpp --json wifi connection </dev/null |
    jq -e '.supplicant_state == "COMPLETED"' >/dev/null
  then
    nightly_result='deferred (Wi-Fi disconnected or unavailable)'
    return 0
  fi

  # Keep the CPU awake for the maintenance; without the lock it still runs.
  if timeout 15 tpp wake-lock acquire >/dev/null 2>&1
  then
    wake_locked=1
  else
    log 'Could not take the wake lock (tpp wake-lock). Continuing without.'
  fi

  free_kib=$(df -k --output=avail "$HOME" | tail -n 1) || return 1
  if [[ ! "$free_kib" =~ ^[[:space:]]*[0-9]+$ ]] || (( free_kib < 524288 ))
  then
    log 'At least 512 MiB of free storage is required.'
    return 1
  fi

  if [[ "$mode" == check ]]
  then
    check_lease || return 1
    nightly_result=ready
  else
    maintenance || return 1
    nightly_result=success
  fi
}

main "$@"

# vim: set ft=sh et ts=2 sw=2 :
