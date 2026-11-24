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
  log "Result: $nightly_result (exit $status)"
  printf 'TermuxPP nightly update: %s (exit %s)\n' "$nightly_result" "$status" >&3
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
    local manifest="${XDG_CONFIG_HOME:-$HOME/.config}/mani/$config.yaml"
    if [[ ! -f "$manifest" ]]
    then
      log "No $config mani config. Skipping."
    elif run_step "mani-$config-sync" 240 mani --config "$manifest" sync
    then
      run_step "mani-$config-update" 480 mani --config "$manifest" run update --all --ignore-non-existing || failed=1
    else
      failed=1
    fi
  done
  return "$failed"
}

main() {
  local mode=update state_dir log_file free_kib
  nightly_result=failed
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
    mv -f -- "$log_file" "$state_dir/previous-run.log" || return 1
  fi
  exec 3>&1 >>"$log_file" 2>&1
  trap 'finish' EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM HUP
  cd "$HOME" || return 1
  log "Starting nightly maintenance ($mode)"

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
