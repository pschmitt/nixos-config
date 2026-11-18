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

upgrade_profile() {
  local pin generations
  log 'Checking the signed cache pin'
  pin=$(timeout --kill-after=15 120 nixpp --json upgrade --from-cache --dry-run |
    jq -er '.path | split("/") | last') || return 1
  generations=$(timeout --kill-after=15 30 nixpp --json status --all) || return 1
  if jq -e --arg pin "$pin" '
    (.[] | select(.current)) as $active |
    any(.[]; .generation == $pin and .number <= $active.number)
  ' <<< "$generations" >/dev/null
  then
    log 'The signed pin is at or behind the active generation. Keeping the active generation.'
    return 0
  fi
  run_step profile 1500 nixpp upgrade --from-cache
}

maintenance() {
  local config failed=0
  upgrade_profile || return 1
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

  if ! timeout 15 termux-battery-status </dev/null |
    jq -e '.plugged != null and .plugged != "UNPLUGGED"' >/dev/null
  then
    nightly_result='deferred (not charging or battery status unavailable)'
    return 0
  fi
  if ! timeout 15 termux-wifi-connectioninfo </dev/null |
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
    run_step profile-check 120 nixpp upgrade --from-cache --dry-run || return 1
    nightly_result=ready
  else
    maintenance || return 1
    nightly_result=success
  fi
}

main "$@"

# vim: set ft=sh et ts=2 sw=2 :
