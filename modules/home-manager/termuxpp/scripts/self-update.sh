#!/usr/bin/env bash

PACKAGE=${TERMUXPP_PACKAGE:-dev.pschmitt.termux}
RUNTIME_DIR=${NIXPP_RUNTIME:-/run/nixpp-runtime}
STATUS_FILE=$RUNTIME_DIR/update-status.json
RECEIVER=$PACKAGE/com.termux.app.update.UpdateCommandReceiver

usage() {
  cat <<EOF_USAGE
Usage: $(basename "$0") [update | check | status | cancel] [--timeout SECONDS]

Update the TermuxPP app itself, with the same updater as Settings > About.

Commands:
  update   Check for a newer build and install it (default)
  check    Only check; exits 0 when up to date, 10 when an update is available
  status   Show the last known updater state
  cancel   Cancel a running check or download

With Shizuku the install needs no confirmation; without it, Android asks.
Installing replaces the app, which ends its processes: this shell may close
before the update finishes. Run "$(basename "$0") status" afterwards.
EOF_USAGE
}

die() {
  printf '%s: %s\n' "$(basename "$0")" "$*" >&2
  exit 1
}

read_status() {
  [[ -r $STATUS_FILE ]] && jq -c . "$STATUS_FILE" 2>/dev/null
}

field() {
  jq -r --arg key "$2" '.[$key] // empty' <<<"$1"
}

show_status() {
  local status
  status=$(read_status) || die "no update status yet in $STATUS_FILE (is the app running?)"
  jq -r '
    "installed: \(.installed // "?")",
    "phase:     \(.phase)",
    (if .offer then "offer:     \(.releaseTag // .offer)" else empty end),
    (if .failure then "failure:   \(.failure)\(if .detail then ": \(.detail)" else "" end)"
     else empty end),
    "updated:   \(.updated | strftime("%Y-%m-%d %H:%M:%S"))"' <<<"$status"
}

send() {
  termux-am broadcast --user "${TERMUX__USER_ID:-0}" -n "$RECEIVER" \
    --es command "$1" >/dev/null || die "cannot reach the TermuxPP app (termux-am failed)"
}

progress() {
  local status=$1 received total
  received=$(field "$status" "done")
  total=$(field "$status" total)
  if [[ -n $received && -n $total && $total -gt 0 ]]
  then
    printf 'downloading: %d%% (%d of %d MiB)' \
      $((received * 100 / total)) $((received >> 20)) $((total >> 20))
  else
    printf 'downloading: %d MiB' $((${received:-0} >> 20))
  fi
}

# Follow the status file until the command reaches a result. Exit codes:
# 0 done or up to date, 10 an update is available (check), 1 failure.
follow() {
  local command=$1 timeout=$2 start=$3
  local status phase last='' installed_before=$4 installed_at_before=$5
  local installed installed_at updated
  local deadline=$((SECONDS + timeout))

  while ((SECONDS < deadline))
  do
    status=$(read_status) || { sleep 1; continue; }
    updated=$(field "$status" updated)
    if ((${updated:-0} < start))
    then
      sleep 1
      continue
    fi
    phase=$(field "$status" phase)
    installed=$(field "$status" installed)
    installed_at=$(field "$status" installedAt)

    # The app restarted with a different build: the install went through.
    if [[ $command == update && -n $installed_at_before && -n $installed_at &&
          $installed_at != "$installed_at_before" ]]
    then
      [[ -t 1 ]] && printf '\n'
      printf 'updated: %s -> %s\n' "$installed_before" "$installed"
      return 0
    fi

    if [[ $phase == DOWNLOADING && -t 1 ]]
    then
      printf '\r\033[K%s' "$(progress "$status")"
    elif [[ $phase != "$last" ]]
    then
      [[ $last == DOWNLOADING && -t 1 ]] && printf '\n'
      case $phase in
        CHECKING) printf 'checking for an update...\n' ;;
        DOWNLOADING) printf '%s\n' "$(progress "$status")" ;;
        VERIFYING) printf 'verifying the download...\n' ;;
        INSTALLING)
          printf 'installing %s; confirm on the phone if Android asks.\n' \
            "$(jq -r '.releaseTag // .offer // "the update"' <<<"$status")"
          printf 'The app restarts and may close this shell.\n'
          ;;
      esac
    fi
    last=$phase

    case $phase in
      UP_TO_DATE)
        printf 'up to date (%s)\n' "${installed:-unknown}"
        return 0
        ;;
      AVAILABLE)
        if [[ $command == check ]]
        then
          printf 'update available: %s (installed %s)\n' \
            "$(jq -r '.releaseTag // .offer' <<<"$status")" "${installed:-unknown}"
          return 10
        fi
        ;;
      NOT_ELIGIBLE)
        printf '%s: the updater cannot replace this build: it has no known release commit\n' \
          "$(basename "$0")" >&2
        printf '(a local build), or the release would downgrade or not install over it.\n' >&2
        printf 'Install a release build of TermuxPP once; later updates then work.\n' >&2
        return 1
        ;;
      UNAVAILABLE|CHECK_FAILED|FAILED)
        printf '%s: %s\n' "$(basename "$0")" \
          "$(jq -r '[.phase, .failure, .detail] | map(select(.)) | join(": ")' <<<"$status")" >&2
        return 1
        ;;
      IDLE)
        # The receiver's own record carries the command and may still show
        # the state from before it; later IDLE means cancelled or restarted.
        if [[ -z $(field "$status" command) ]]
        then
          printf 'the updater went idle without installing (cancelled?)\n' >&2
          return 1
        fi
        ;;
    esac
    sleep 1
  done
  [[ -t 1 ]] && printf '\n'
  die "no result after ${timeout}s; see $(basename "$0") status"
}

main() {
  local command=update timeout=900

  while (($# > 0))
  do
    case $1 in
      update|check|status|cancel) command=$1 ;;
      --timeout)
        [[ ${2:-} =~ ^[0-9]+$ ]] || die "--timeout needs a number of seconds"
        timeout=$2
        shift
        ;;
      -h|--help)
        usage
        return 0
        ;;
      *)
        usage >&2
        return 2
        ;;
    esac
    shift
  done

  case $command in
    status)
      show_status
      return
      ;;
    cancel)
      send cancel
      return
      ;;
  esac

  local before installed_before='' installed_at_before='' start
  if before=$(read_status)
  then
    installed_before=$(field "$before" installed)
    installed_at_before=$(field "$before" installedAt)
  fi
  start=$(date +%s)
  send "$command"
  follow "$command" "$timeout" "$start" "$installed_before" "$installed_at_before"
}

main "$@"

# vim: set ft=sh et ts=2 sw=2 :
