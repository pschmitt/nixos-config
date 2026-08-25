# shellcheck shell=bash

selection=clipboard
requested_type=
no_newline=0
watch_command=()

print_help() {
  cat <<'EOF'
Usage:
  wl-paste [options]

Paste content from the clipboard.

Options:
  -n, --no-newline       Do not append a newline character.
  -l, --list-types       Instead of pasting, list the offered types.
  -p, --primary          Use the primary clipboard.
  -w, --watch command    Run a command each time the selection changes.
  -t, --type mime/type   Override the inferred MIME type for the content.
  -s, --seat seat-name   Pick a seat (accepted for compatibility).
  -v, --version          Display version info.
  -h, --help             Display this message.
EOF
}

print_version() {
  cat <<'EOF'
wl-clipboard 2.2.1
Copyright (C) 2018-2025 Sergey Bugaev
License GPLv3+: GNU GPL version 3 or later <https://gnu.org/licenses/gpl.html>.
This is free software: you are free to change and redistribute it.
There is NO WARRANTY; not even for MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
EOF
}

set_display() {
  DISPLAY=:99
  export DISPLAY
}

offered_targets() {
  xclip -selection "$selection" -target TARGETS -out
}

is_internal_target() {
  case "$1" in
    ATOM|ATOM_PAIR|INCR|MULTIPLE|SAVE_TARGETS|TARGETS|TIMESTAMP)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

filtered_targets() {
  local target
  while IFS= read -r target
  do
    target="${target//$'\r'/}"
    [[ -z "$target" ]] && continue
    is_internal_target "$target" && continue
    printf '%s\n' "$target"
  done
}

target_is_offered() {
  local wanted="$1"
  local targets="$2"
  local target

  while IFS= read -r target
  do
    target="${target//$'\r'/}"
    [[ "$target" == "$wanted" ]] && return 0
  done <<< "$targets"

  return 1
}

candidate_targets() {
  local targets="$1"
  local preferred target duplicate
  local -a preferred_targets=(
    image/png
    image/jpeg
    image/webp
    image/gif
    image/bmp
    image/tiff
    "text/plain;charset=utf-8"
    text/plain
    UTF8_STRING
    STRING
    TEXT
  )

  for preferred in "${preferred_targets[@]}"
  do
    target_is_offered "$preferred" "$targets" && printf '%s\n' "$preferred"
  done

  while IFS= read -r target
  do
    target="${target//$'\r'/}"
    [[ -z "$target" ]] && continue
    is_internal_target "$target" && continue

    duplicate=0
    for preferred in "${preferred_targets[@]}"
    do
      if [[ "$target" == "$preferred" ]]
      then
        duplicate=1
        break
      fi
    done
    (( duplicate )) && continue

    printf '%s\n' "$target"
  done <<< "$targets"
}

read_target() {
  local target="$1"
  local output="$2"
  local -a xclip_args=( -selection "$selection" -target "$target" -out )
  xclip "${xclip_args[@]}" >"$output"
}

read_clipboard() {
  local targets="$1"
  local output="$2"
  local target

  if [[ -n "$requested_type" ]]
  then
    read_target "$requested_type" "$output"
    return
  fi

  while IFS= read -r target
  do
    if read_target "$target" "$output" 2>/dev/null
    then
      return 0
    fi
  done < <(candidate_targets "$targets")

  return 1
}

paste_once() {
  local targets temporary rc
  targets="$(offered_targets)" || return 1
  temporary="$(mktemp)"

  if ! read_clipboard "$targets" "$temporary"
  then
    rm -f "$temporary"
    [[ -n "$requested_type" ]] || printf 'wl-paste: no usable clipboard target available\n' >&2
    return 1
  fi

  if cat "$temporary"
  then
    rc=0
  else
    rc=$?
  fi
  if (( ! no_newline )) && (( rc == 0 ))
  then
    printf '\n'
  fi
  rm -f "$temporary"
  return "$rc"
}

watch_clipboard() {
  local temporary current targets previous=''
  temporary="$(mktemp)"
  trap 'rm -f "$temporary"' EXIT

  while true
  do
    targets="$(offered_targets 2>/dev/null || true)"

    if read_clipboard "$targets" "$temporary" 2>/dev/null
    then
      current="$(sha256sum "$temporary")"
      if [[ "$current" != "$previous" ]]
      then
        previous="$current"
        "${watch_command[@]}" <"$temporary" || true
      fi
    fi

    sleep 0.1
  done
}

while [[ $# -gt 0 ]]
do
  case "$1" in
    -n|--no-newline)
      no_newline=1
      shift
      ;;
    -l|--list-types)
      set_display
      targets="$(offered_targets)" || exit 1
      filtered_targets <<< "$targets"
      exit 0
      ;;
    -p|--primary)
      selection=primary
      shift
      ;;
    -t|--type)
      [[ -n "${2:-}" ]] || { printf 'wl-paste: option requires an argument -- t\n' >&2; exit 2; }
      requested_type="$2"
      shift 2
      ;;
    --type=*)
      requested_type="${1#*=}"
      shift
      ;;
    -t?*)
      requested_type="${1#-t}"
      shift
      ;;
    -s|--seat)
      [[ -n "${2:-}" ]] || { printf 'wl-paste: option requires an argument -- s\n' >&2; exit 2; }
      shift 2
      ;;
    --seat=*)
      shift
      ;;
    -w|--watch)
      shift
      [[ $# -gt 0 ]] || { printf 'wl-paste: --watch requires a command\n' >&2; exit 2; }
      watch_command=( "$@" )
      break
      ;;
    -v|--version)
      print_version
      exit 0
      ;;
    -h|--help)
      print_help
      exit 0
      ;;
    --)
      shift
      [[ $# -eq 0 ]] || { printf 'wl-paste: unexpected argument: %s\n' "$1" >&2; exit 2; }
      ;;
    -*|*)
      printf 'wl-paste: unrecognized option: %s\n' "$1" >&2
      exit 2
      ;;
  esac
done

set_display
if [[ ${#watch_command[@]} -gt 0 ]]
then
  watch_clipboard
else
  paste_once
fi

# vim: set ft=sh et ts=2 sw=2 :
