# ms-teams — Nix-native replacement for the zhj ms-teams:: helpers used in
# this repo: meeting lookup (url/title) from the meetings JSON, and an
# in-a-meeting check backed by bruvtab (browser tab listing).
#
# Only the subcommands referenced by the repo are ported (in-a-meeting, url,
# title, data). join-meeting / close-tabs are left in the zsh helpers.

MEETINGS_FILE="${MS_TEAMS_MEETINGS_FILE:-${HOME}/Documents/data/ms-teams-meetings.json}"

# Look up a meeting by slug/display_name/title (exact first, then fuzzy on
# display_name). With PROP, print that single property; otherwise the object.
meeting_data() {
  local name="$1" prop="${2:-}"

  if [[ -z "$name" ]]
  then
    echo "usage: ms-teams data NAME [PROP]" >&2
    return 2
  fi

  if [[ ! -r "$MEETINGS_FILE" ]]
  then
    echo "meetings file not found: $MEETINGS_FILE" >&2
    return 1
  fi

  local res
  if ! res="$(jq -er --arg meeting_name "$name" '
      ($meeting_name | ascii_downcase | gsub(" +"; "-")) as $slug_guess
      | def exact:
          .slug == $meeting_name
          or .slug == $slug_guess
          or .display_name == $meeting_name
          or .title == $meeting_name;
        def fuzzy:
          .display_name | test($meeting_name; "i");
        ([ .[] | select(exact) ]) as $exact
        | if ($exact | length) > 0 then $exact else [ .[] | select(fuzzy) ] end
    ' "$MEETINGS_FILE")"
  then
    echo "No meeting found matching '$name'" >&2
    return 1
  fi

  local count
  count="$(jq -r 'length' <<< "$res")"

  if [[ "$count" -eq 0 ]]
  then
    echo "No meeting found matching '$name'" >&2
    return 1
  fi

  if [[ "$count" -gt 1 ]]
  then
    echo "Multiple meetings found matching '$name'" >&2
    jq -r '.[].display_name' <<< "$res" | sed 's/^/ - /' >&2
    return 1
  fi

  if [[ -n "$prop" ]]
  then
    if ! jq -er --arg prop "$prop" '.[0][$prop]' <<< "$res"
    then
      echo "Property '$prop' not found for '$name'" >&2
      return 1
    fi
    return 0
  fi

  jq -e '.[0]' <<< "$res"
}

in_a_meeting() {
  if bruvtab list 2>/dev/null | grep -qE '(teams\.microsoft\.com/v2|teams\.cloud\.microsoft)'
  then
    echo "Currently attending a meeting" >&2
  else
    echo "*NOT* in a meeting" >&2
    return 1
  fi
}

case "${1:-}" in
  in-a-meeting)
    in_a_meeting
    ;;
  url)
    shift
    meeting_data "${1:-}" url
    ;;
  title)
    shift
    meeting_data "${1:-}" title
    ;;
  data)
    shift
    meeting_data "$@"
    ;;
  "" | -h | --help | help)
    echo "Usage: ms-teams {in-a-meeting|url NAME|title NAME|data NAME [PROP]}" >&2
    [[ "${1:-}" == "" ]] && exit 2 || exit 0
    ;;
  *)
    echo "Unknown command: $1" >&2
    exit 2
    ;;
esac
