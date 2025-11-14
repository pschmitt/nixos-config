#!/usr/bin/env bash

usage() {
  echo "Usage: $(basename "$0") [ARGS] COMMAND"
  echo
  echo "ARGS:"
  echo
  echo "  -s|--sleep SECONDS       How long to wait for before restarting (default: 2)"
  echo "  --single-instance        Only allow one instance of this script to run at a time"
  echo "  --journal-identifier ID  Identifier to use for journald"
  echo "  --restart ID             Restart the process"
  echo "  --source FILE            Source this file before running the command"
  echo "  --kill-cmd CMD           Command to run before killing the process"
}

zhj() {
  "${HOME}/bin/zhj" "$@"
}

hyprland_instance_signature() {
  zhj hyperctl::instance-signature
}

# https://unix.stackexchange.com/a/124148
list_descendants() {
  local pid children
  children=$(ps -o pid= --ppid "$1")

  for pid in $children
  do
    list_descendants "$pid"
  done

  if [[ -n "$children" ]]
  then
    echo "$children"
  fi
}


if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
  SLEEP_INTERVAL="1"
  CMD_AFTER=""

  while [[ -n "$*" ]]
  do
    case "$1" in
      --sleep)
        SLEEP_INTERVAL="$2"
        if ! [[ "$SLEEP_INTERVAL" =~ ^[0-9]+$ ]]
        then
          echo "error: Not a number" >&2
          exit 2
        fi
        shift 2
        ;;
      --single-instance|-s)
        SINGLE_INSTANCE=1
        shift
        ;;
      -j|--journal-identifier|--identifier)
        JOURNAL_IDENTIFIER="$2"
        shift 2
        ;;
      -S|--source)
        SOURCE_FILE="$2"
        shift 2
        ;;
      -k|--kill-cmd|-a|--after)
        CMD_AFTER="$2"
        shift 2
        ;;
      -r|--restart)
        RESTART_ID="$2"
        shift 2
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      --)
        shift
        break
        ;;
      *)
        break
        ;;
    esac
  done

  if [[ -n "$RESTART_ID" ]]
  then
    SELF="bash .+$(basename "$0") .+ ${RESTART_ID}"
    mapfile -t SELF_PIDS < <(pgrep -f "$SELF")

    if [[ -z "${SELF_PIDS[*]}" ]]
    then
      echo "No process found for \"$SELF\"" >&2
      exit 1
    fi
    # We will have multiple pids here since pgrep will return the children of
    # this here's process (ie the pgrep subshell itself?)
    RC=1
    for PID in "${SELF_PIDS[@]}"
    do
      # Check if the process is still alive
      if ! kill -0 "$PID" &>/dev/null
      then
        continue
      fi
kill -0 1087878
      echo "Killing children of $PID" >&2
      mapfile -t CHILDREN < <(list_descendants "$PID")
      if [[ -n "${CHILDREN[*]}" ]]
      then
        kill -- "${CHILDREN[@]}"
        RC="$?"
      else
        echo "No children found for $PID" >&2
      fi
    done

    exit "$RC"
  fi

  CMD=("$@")

  if [[ -n "$SINGLE_INSTANCE" ]]
  then
    SELF="bash $0 .+ ${CMD[*]}"
    if pgrep -af "$SELF" | grep -v "$$"
    then
      echo "There's already an instance of \"$SELF\" running" >&2
      exit 1
    fi
  fi

  if [[ -z "${CMD[*]}" ]]
  then
    {
      echo "Missing command"
      usage
    } >&2
    exit 2
  fi

  if [[ -n "$JOURNAL_IDENTIFIER" ]]
  then
    CMD=(systemd-cat --identifier="$JOURNAL_IDENTIFIER" "${CMD[@]}")
  fi

  # Exit on Ctrl+C
  trap 'exit 127' SIGINT

  while :
  do
    # shellcheck disable=1090
    [[ -n "$SOURCE_FILE" ]] && source "$SOURCE_FILE"

    # Update HYPRLAND_INSTANCE_SIGNATURE (might be required for waybar for eg.)
    # shellcheck disable=2155
    export HYPRLAND_INSTANCE_SIGNATURE="$(hyprland_instance_signature)"

    "${CMD[@]}"

    # {
    #   echo "🧟 It's dead, Jim! Restarting \"${CMD[*]}\" in ${SLEEP_INTERVAL} second(s)"
    #   echo "Killing subprocesses..."
    #   echo "My own pid is: $$"
    # } >&2

    # # shellcheck disable=2009
    # mapfile -t CHILDREN < <(
    #   ps --forest -o pid= -g "$(ps -o sid= -p "$$" | awk '{ print $1 }')" | \
    #     awk '{ print $1 }' | \
    #     grep -v "$$"
    # )

    # if [[ -n "${CHILDREN[*]}" ]]
    # then
    #   echo "kill ${CHILDREN[*]}" >&2
    #   kill "${CHILDREN[@]}"
    # fi

    sleep "$SLEEP_INTERVAL"

    if [[ -n "$CMD_AFTER" ]]
    then
      # shellcheck disable=1090
      [[ -n "$SOURCE_FILE" ]] && source "$SOURCE_FILE"
      "${CMD_AFTER[@]}"
    fi
  done
fi
