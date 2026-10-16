# shellcheck shell=bash

# Restart audio stack units, unless the Meeting Microphone is in use.
#
# Restarting PipeWire kills every client stream, and Teams (web) does not
# reopen a microphone it lost: a live call ends up without a mic until it is
# re-joined. Config changes are therefore only applied when no app records
# from the Meeting Microphone; otherwise the restart is left to the user.

MIC_NODE="${MIC_NODE:-meeting_source}"

usage() {
  cat <<EOF
Usage: $(basename "$0") UNIT...

try-restart the given systemd user units unless something records from the
$MIC_NODE PipeWire node.
EOF
}

mic_in_use() {
  pw-dump 2>/dev/null | jq -e --arg mic "$MIC_NODE" '
    [.[] | select(.type == "PipeWire:Interface:Node"
      and .info.props["node.name"] == $mic) | .id] as $ids
    | any(.[]; .type == "PipeWire:Interface:Link"
      and (.info["output-node-id"] as $id | $ids | index($id)))' >/dev/null
}

main() {
  case "${1:-}" in
    -h|--help)
      usage
      return 0
      ;;
    "")
      usage >&2
      return 2
      ;;
  esac

  if mic_in_use
  then
    echo "$MIC_NODE is in use (call in progress?), not restarting $*." >&2
    echo "Apply the audio config later: systemctl --user restart $*" >&2
    return 0
  fi

  systemctl --user try-restart "$@"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
  main "$@"
  exit $?
fi

# vim: set ft=sh et ts=2 sw=2 :
