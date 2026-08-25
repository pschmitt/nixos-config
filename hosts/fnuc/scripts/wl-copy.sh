# shellcheck shell=bash

selection=clipboard
requested_type=
trim_newline=0
paste_once=0
foreground=0
clear_clipboard=0
data=()

print_help() {
  cat <<'EOF'
Usage:
  wl-copy [options] text to copy
  wl-copy [options] < file-to-copy

Copy content to the clipboard.

Options:
  -o, --paste-once      Only serve one paste request and then exit.
  -f, --foreground      Stay in the foreground instead of forking.
  -c, --clear           Instead of copying, clear the clipboard.
  -p, --primary         Use the primary clipboard.
  -n, --trim-newline    Do not copy the trailing newline character.
  -t, --type mime/type  Override the inferred MIME type for the content.
      --sensitive       Hint that the content is sensitive.
  -s, --seat seat-name  Pick a seat (accepted for compatibility).
  -v, --version         Display version info.
  -h, --help            Display this message.
EOF
}

print_version() {
  cat <<'EOF'
wl-clipboard 2.2.1
Copyright (C) 2018-2025 Sergey Bugaev
License GPLv3+: GNU GPL version 3 or later <https://gnu.org/licenses/gpl.html>.
This is free software: you can change and redistribute it.
There is NO WARRANTY; not even for MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
EOF
}

set_display() {
  DISPLAY="${DISPLAY:-:99}"
  export DISPLAY
}

write_input() {
  if [[ ${#data[@]} -gt 0 ]]
  then
    printf '%s' "${data[*]}"
  else
    cat
  fi
}

run_xclip() {
  local -a xclip_args=(
    -selection "$selection"
    -in
    -loops "$paste_once"
    -silent
  )

  [[ -n "$requested_type" ]] && xclip_args+=( -target "$requested_type" )

  if (( foreground )); then
    if (( trim_newline )); then
      write_input | perl -0777 -pe 's/\n\z//' | xclip "${xclip_args[@]}"
    else
      write_input | xclip "${xclip_args[@]}"
    fi
  elif (( trim_newline ))
  then
    write_input | perl -0777 -pe 's/\n\z//' | nohup xclip "${xclip_args[@]}" >/dev/null 2>&1 &
  else
    write_input | nohup xclip "${xclip_args[@]}" >/dev/null 2>&1 &
  fi
}

clear_xclip() {
  xclip -selection "$selection" -in -loops 1 -silent </dev/null
}

while [[ $# -gt 0 ]]
do
  case "$1" in
    -o|--paste-once)
      paste_once=1
      shift
      ;;
    -f|--foreground)
      foreground=1
      shift
      ;;
    -c|--clear)
      clear_clipboard=1
      shift
      ;;
    -p|--primary)
      selection=primary
      shift
      ;;
    -n|--trim-newline)
      trim_newline=1
      shift
      ;;
    -t|--type)
      [[ -n "${2:-}" ]] || { printf 'wl-copy: option requires an argument -- t\n' >&2; exit 2; }
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
    --sensitive)
      shift
      ;;
    -s|--seat)
      [[ -n "${2:-}" ]] || { printf 'wl-copy: option requires an argument -- s\n' >&2; exit 2; }
      shift 2
      ;;
    --seat=*)
      shift
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
      data+=( "$@" )
      break
      ;;
    -* )
      printf 'wl-copy: unrecognized option: %s\n' "$1" >&2
      exit 2
      ;;
    *)
      data+=( "$1" )
      shift
      ;;
  esac
done

if (( clear_clipboard )) && [[ ${#data[@]} -gt 0 ]]
then
  printf 'wl-copy: --clear cannot be combined with data\n' >&2
  exit 2
fi

set_display
if (( clear_clipboard ))
then
  if (( foreground )); then
    clear_xclip
  else
    nohup xclip -selection "$selection" -in -loops 1 -silent </dev/null >/dev/null 2>&1 &
    disown
  fi
else
  run_xclip
  if (( ! foreground )); then
    disown
  fi
fi

# vim: set ft=sh et ts=2 sw=2 :
