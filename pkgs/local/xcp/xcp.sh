
export DISPLAY="${DISPLAY:-:0}"
# CLIPPER_PORT can be set to override the port detection mechanism
# $ echo test | CLIPPER_PORT=18377 xcp
# MIMETYPE can be set to indicate that the first argument is a file path and
# should be copied as that mimetype (similar to SELECTION).
CLIPPER_PORT="${CLIPPER_PORT:-}"
CLIPPER_LOCAL_PORT="${CLIPPER_LOCAL_PORT:-8377}"
CLIPPER_REMOTE_PORT="${CLIPPER_REMOTE_PORT:-8378}"

is_termux() {
  command -v termux-info > /dev/null
}

is_ssh() {
  [[ -n "${SSH_CONNECTION:-}" ]]
}

is_wayland() {
  if [[ "$XDG_SESSION_TYPE" == "wayland" || -n "$WAYLAND_DISPLAY" ]]
  then
    return 0
  fi

  return 1
}

guess_wayland_display() {
  local XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-/run/user/$(id -u)}
  local s
  for s in "${XDG_RUNTIME_DIR}"/wayland-*
  do
    if [[ -S "$s" ]]
    then
      first="${s##*/}"
      break
    fi
  done

  printf '%s\n' "$first"
}
export WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-$(guess_wayland_display)}"

has() {
  command -v "$1" > /dev/null
}

has_xsel() {
  has xsel
}

has_xclip() {
  has xclip
}

has_wl-copy() {
  has wl-copy
}

xclip_first_image_target() {
  local selection="$1"
  local targets

  if ! targets="$(xclip -selection "$selection" -out -t TARGETS 2>/dev/null)"
  then
    return 1
  fi

  while IFS= read -r target
  do
    case "$target" in
      image/*)
        printf '%s\n' "$target"
        return 0
        ;;
    esac
  done <<< "$targets"

  return 1
}

xsel_first_image_target() {
  local selection="$1"
  local targets

  if ! targets="$(xsel --output "--${selection}" --target TARGETS 2>/dev/null)"
  then
    return 1
  fi

  while IFS= read -r target
  do
    case "$target" in
      image/*)
        printf '%s\n' "$target"
        return 0
        ;;
    esac
  done <<< "$targets"

  return 1
}

has_lemonade() {
  has lemonade
}

guess_mime_type() {
  local path="$1"

  if has file
  then
    file --brief --mime-type "$path" 2>/dev/null
  fi
}

stdin_is_binary() {
  local path="$1"

  if [[ ! -s "$path" ]]
  then
    return 1
  fi

  # Prefer `file`'s encoding classifier when available.
  if has file
  then
    [[ "$(file --brief --mime-encoding "$path" 2>/dev/null)" == "binary" ]]
    return $?
  fi

  # Fallback: treat any NUL byte as "binary".
  # NOTE We can't reliably embed a NUL byte in a shell string, so count them
  # instead of searching for a literal.
  if has tr && has wc
  then
    local nul_count
    nul_count="$(LC_ALL=C tr -cd '\000' < "$path" 2>/dev/null | wc -c | tr -d ' ')"
    if [[ "$nul_count" =~ ^[0-9]+$ ]] && (( nul_count > 0 ))
    then
      return 0
    fi

    return 1
  fi

  # Last resort: detect NUL bytes via hex dump.
  LC_ALL=C od -An -tx1 -v "$path" 2>/dev/null | tr -d ' \n' | grep -q '00'
}

has_kitty() {
  if ! has kitten
  then
    return 1
  fi

  case "$TERM" in
    *kitty*)
      ;;
    *)
      return 1
      ;;
  esac

  if [[ "$TERM_PROGRAM" == "kitty" || -n "$KITTY_WINDOW_ID" ]]
  then
    return 0
  fi

  return 1
}

_nc() {
  (
    cat < /dev/null > "/dev/tcp/${1}/${2}"
  ) 2>/dev/null
}

clipper_running() {
  local clipper_port
  local cmd_prefix

  clipper_port="$(clipper_get_port)"

  if is_termux
  then
    cmd_prefix="sudo"
  fi

  # NOTE Do not use nc -z here since this will actually clear the clipboard
  $cmd_prefix ss -4tlnp 2>/dev/null | grep -q "127.0.0.1:${clipper_port}"
}

clipper_get_port() {
  if [[ -n "$CLIPPER_PORT" ]]
  then
    echo "$CLIPPER_PORT"
  elif [[ -n "$SSH_CONNECTION" ]]
  then
    echo "$CLIPPER_REMOTE_PORT"
  else
    echo "$CLIPPER_LOCAL_PORT"
  fi
}

echo_error() {
  local message="$*"

  printf '%b\n' "\e[1;31mERR\e[0m ${message}" >&2

  if [[ -n "$NOTIFY" ]]
  then
    notify-send --app-name "xcp" --category "error" "$message"
  fi
}

echo_info() {
  local message="$*"

  printf '%b\n' "\e[1;34mINF\e[0m ${message}" >&2

  if [[ -n $NOTIFY ]]
  then
    notify-send --app-name "xcp" --category "info" "$message"
  fi
}

echo_success() {
  local message="$*"

  printf '%b\n' "\e[1;32mOK\e[0m ${message}" >&2

  if [[ -n $NOTIFY ]]
  then
    notify-send --app-name "xcp" --category "success" "$message"
  fi
}

echo_debug() {
  [[ -n "$DEBUG" ]] || return 0

  local message="$*"
  printf '%b\n' "\e[1;35mDBG\e[0m ${message}" >&2
  logger "xcp: $*"
}

notify_send() {
  local extra_args=()

  if [[ -n "$NOTIFY_ICON" ]]
  then
    extra_args+=("--icon=${NOTIFY_ICON}")
  elif [[ -e /usr/share/icons/breeze-dark/apps/48/klipper.svg ]]
  then
    extra_args+=("--icon=/usr/share/icons/breeze-dark/apps/48/klipper.svg")
  fi

  notify-send -a "$(basename "$0")" "${extra_args[@]}" "$@"
}

notify_success() {
  if [[ -z "$NOTIFY" ]]
  then
    return
  fi

  local message="Clipboard set"

  case "$NOTIFY" in
    1)
      # nothing to do, keep message as is
      ;;
    value)
      message="${message} to \"${1}\""
      ;;
    *)
      message="${message} to ${NOTIFY}"
      ;;
  esac

  notify_send -t 3000 "✔️ $message"
}

check_success() {
  local clipboard="$1"
  local desired_output="$2"

  if [[ "$clipboard" != "$desired_output" ]]
  then
    return 3
  fi

  notify_success "$desired_output"
  return 0
}

verify_clipboard() {
  local name="$1"
  local content="$2"
  local clipboard
  clipboard="$(get_clipboard_content "$name")"

  echo_debug "${name}: \"${clipboard}\" vs \"$content\""
  check_success "$clipboard" "$content"
}

try_wl-copy() {
  if ! has_wl-copy
  then
    return 1
  fi

  local mime_type="${MIMETYPE:-}"
  local sel="${SELECTION:-clipboard}"

  if [[ -n "$mime_type" ]]
  then
    echo_debug "wl-copy mode: file (type=$mime_type, selection=$sel, path=$1)"
  else
    echo_debug "wl-copy mode: text (selection=$sel)"
  fi

  local extra_args=()
  if [[ -n "$mime_type" ]]
  then
    extra_args+=(--type "$mime_type")
  fi

  case "$sel" in
    clipboard)
      if [[ -n "$mime_type" ]]
      then
        wl-copy "${extra_args[@]}" < "$1"
      else
        printf '%s' "$1" | wl-copy
      fi
      ;;
    primary)
      if [[ -n "$mime_type" ]]
      then
        wl-copy --primary "${extra_args[@]}" < "$1"
      else
        printf '%s' "$1" | wl-copy --primary
      fi
      ;;
    both)
      if [[ -n "$mime_type" ]]
      then
        wl-copy "${extra_args[@]}" < "$1"
        wl-copy --primary "${extra_args[@]}" < "$1"
      else
        printf '%s' "$1" | wl-copy
        printf '%s' "$1" | wl-copy --primary
      fi
      ;;
    *)
      echo "Unknown selection name: $sel" >&2
      return 2
      ;;
  esac

  local rc="$?"
  if [[ "$rc" -ne 0 ]]
  then
    return "$rc"
  fi

  if [[ -n "$mime_type" ]]
  then
    echo_debug "wl-copy: skipping verification for mime-typed content"
    return 0
  fi

  verify_clipboard wl-paste "$1"
}

try_clipper() {
  if [[ -n "$SKIP_CLIPPER" ]]
  then
    # Return here to avoid an infinite loop of clipper calling xcp,
    # xcp echoing to clippers socket/port and it in turn launching xcp
    echo_debug "Clipper SKIPPED."
    return 1
  fi

  if ! clipper_running
  then
    return 1
  fi

  local clipper_port
  clipper_port="$(clipper_get_port)"

  if ! printf '%s' "$1" | _nc 127.0.0.1 "$clipper_port"
  then
    return 3
  fi

  # Don't attempt to compare with the local clipboard since we are setting the
  # clipper server clipboard
  if [[ -n "$SSH_CONNECTION" ]]
  then
    echo_debug "Set remote clipboard via clipper to \"$1\""
  else
    verify_clipboard clipper "$1"
  fi
}

try_kitty() {
  if ! has_kitty
  then
    return 1
  fi

  printf '%s' "$1" | kitten clipboard
}

try_lemonade() {
  if ! has_lemonade
  then
    return 1
  fi

  printf '%s' "$1" | lemonade copy
}

try_xclip() {
  if ! has_xclip
  then
    return 1
  fi

  local mime_type="${MIMETYPE:-}"
  local sel="${SELECTION:-clipboard}"

  if [[ -n "$mime_type" ]]
  then
    echo_debug "xclip mode: file (type=$mime_type, selection=$sel, path=$1)"
  else
    echo_debug "xclip mode: text (selection=$sel)"
  fi

  case "$sel" in
    primary|secondary|clipboard)
      local extra_args=(-selection "$sel")
      if [[ -n "$mime_type" ]]
      then
        extra_args+=(-t "$mime_type")
        xclip -in "${extra_args[@]}" < "$1" 2>/dev/null
      else
        printf '%s' "$1" | xclip -in "${extra_args[@]}" 2>/dev/null
      fi
      ;;
    both)
      for sel in primary clipboard
      do
        if [[ -n "$mime_type" ]]
        then
          xclip -in -selection "$sel" -t "$mime_type" < "$1" 2>/dev/null
        else
          printf '%s' "$1" | xclip -in -selection "$sel" 2>/dev/null
        fi
      done
      ;;
    *)
      echo "Unknown selection name: $sel" >&2
      return 2
      ;;
  esac

  local rc="$?"
  if [[ "$rc" -ne 0 ]]
  then
    return "$rc"
  fi

  if [[ -n "$mime_type" ]]
  then
    echo_debug "xclip: skipping verification for mime-typed content"
    return 0
  fi

  verify_clipboard xclip "$1"
}

try_xsel() {
  if ! has_xsel
  then
    return 1
  fi

  local sel="${SELECTION:-clipboard}"

  case "$sel" in
    primary|secondary|clipboard)
      local extra_args=("--${sel}")
      printf '%s' "$1" | xsel --input "${extra_args[@]}"
      ;;
    both)
      for sel in primary clipboard
      do
        printf '%s' "$1" | xsel --input "--${sel}"
      done
      ;;
    *)
      echo "Unknown selection name: $sel" >&2
      return 2
      ;;
  esac

  verify_clipboard xsel "$1"
}

try_osc52() {
  local text="$1"

  local text_enc
  text_enc="$(printf %s "$text" | base64 -w 0 | tr -d '\n')"

  # osc52 ; c ; text ST
  printf "\033]52;c;%s\a" "$text_enc"

  # TODO Verify the clipboard content using osc52!
  # verify_clipboard osc52 "$text"

  local content
  # content="$(get_clipboard_content)"
  content="$text" # that's CHEATING but we cannot get it back yet
  check_success "$content" "$text"
}

try_termux-clipboard() {
  local text="$1"
  termux-clipboard-set "$text"
  verify_clipboard termux-clipboard "$text"
}

get_clipboard_content() {
  local backend="$1"
  local extra_args=()
  local content

  local SELECTION="${SELECTION:-clipboard}"

  if [[ "$SELECTION" == "both" ]]
  then
    SELECTION=clipboard
  fi

  if [[ -z "$backend" ]]
  then
    if is_termux
    then
      backend="termux-clipboard"
    elif is_wayland
    then
      backend="wl-paste"
    else
      if has_xclip
      then
        local image_target
        if image_target="$(xclip_first_image_target "$SELECTION")"
        then
          backend="xclip"
        fi
      fi

      if [[ -z "$backend" ]] && has_xsel
      then
        local image_target
        if image_target="$(xsel_first_image_target "$SELECTION")"
        then
          backend="xsel"
        fi
      fi

      if [[ -z "$backend" ]]
      then
        if has_kitty
        then
          backend="kitty"
        elif has_lemonade
        then
          backend="lemonade"
        elif has_xclip
        then
          backend="xclip"
        elif has_xsel
        then
          backend="xsel"
        else
          echo_debug "Neither lemonade, xclip nor xsel are installed"
          return 1
        fi
      fi
    fi
  fi

  case "$backend" in
    wl-paste)
      if [[ "$SELECTION" == "primary" ]]
      then
        extra_args+=(--primary)
      fi

      # check for image types
      local imgtypes
      mapfile -t imgtypes < <(
        wl-paste --list-types "${extra_args[@]}" | grep '^image/'
      )

      # manually set mimetype if provided
      local mime_type=""
      if [[ -n "$MIMETYPE" ]]
      then
        mime_type="$MIMETYPE"
        extra_args+=(--type "$MIMETYPE")
      elif [[ ${#imgtypes[@]} -gt 0 ]]
      then
        # output image
        mime_type="${imgtypes[0]}"
        extra_args+=(--type "$mime_type")
      fi

      echo_debug "clipboard getter: wl-paste (selection=$SELECTION)"
      echo_debug "wl-paste extra args: ${extra_args[*]}"

      if [[ -n "$mime_type" && "$mime_type" == image/* ]]
      then
        wl-paste --no-newline "${extra_args[@]}"
        return "$?"
      fi

      local cmd=(wl-paste --no-newline "${extra_args[@]}")
      if ! content="$("${cmd[@]}")"
      then
        echo_debug "wl-paste failed."
        return 1
      fi

      printf '%s' "$content"
      ;;
    kitty)
      if [[ "$SELECTION" == "primary" ]]
      then
        extra_args+=(--use-primary)
      fi

      if ! content="$(kitten clipboard --get-clipboard "${extra_args[@]}")"
      then
        echo_debug "kitty clipboard getter failed."
        return 1
      fi

      echo_info "clipboard getter: kitty (selection=$SELECTION)"
      printf '%s' "$content"
      ;;
    lemonade)
      if ! content="$(timeout 10 lemonade paste)"
      then
        local rc="$?"
        echo_debug "lemonade paste failed. It probably timed out? (rc=$rc)"
        return "$rc"
      fi

      echo_info "clipboard getter: lemonade (selection=$SELECTION)"
      printf '%s' "$content"
      ;;
    osc52)
      # FIXME This does not work yet
      local content_b64
      content_b64=$(printf '\033]52;c;?\a' | awk -F'c;' '{print $2}' | tr -d '\a')
      base64 --decode <<< "$content_b64"
      ;;
    termux-clipboard)
      if ! content="$(termux-clipboard-get)"
      then
        echo_debug "termux-clipboard-get failed."
        return 1
      fi

      echo_info "clipboard getter: termux-clipboard"
      printf '%s' "$content"
      ;;
    xclip)
      extra_args+=(-selection "$SELECTION")
      local mime_type=""
      if [[ -n "$MIMETYPE" ]]
      then
        mime_type="$MIMETYPE"
      else
        mime_type="$(xclip_first_image_target "$SELECTION")"
      fi

      if [[ -n "$mime_type" && "$mime_type" == image/* ]]
      then
        echo_info "clipboard getter: xclip (selection=$SELECTION, type=$mime_type)"
        xclip -out -t "$mime_type" "${extra_args[@]}"
        return "$?"
      fi

      if ! content="$(xclip -out "${extra_args[@]}")"
      then
        echo_debug "xclip getter failed."
        return 1
      fi

      echo_info "clipboard getter: xclip (selection=$SELECTION)"
      printf '%s' "$content"
      ;;
    xsel)
      extra_args+=("--${SELECTION}")
      local mime_type=""
      if [[ -n "$MIMETYPE" ]]
      then
        mime_type="$MIMETYPE"
      else
        mime_type="$(xsel_first_image_target "$SELECTION")"
      fi

      if [[ -n "$mime_type" && "$mime_type" == image/* ]]
      then
        echo_info "clipboard getter: xsel (selection=$SELECTION, type=$mime_type)"
        xsel "${extra_args[@]}" --output --target "$mime_type"
        return "$?"
      fi

      if ! content="$(xsel "${extra_args[@]}" --output)"
      then
        echo_debug "xsel getter failed."
        return 1
      fi

      echo_info "clipboard getter: xsel (selection=$SELECTION)"
      printf '%s' "$content"
      ;;
    *)
      echo_debug "Neither wl-clipboard, lemonde, xclip nor xsel are available"
      return 1
      ;;
  esac
}

set_tmux_buffer() {
  if [[ -z "$TMUX" ]]
  then
    return
  fi

  # NOTE We cannot use set-buffer here it will fail with "Argument list too
  # long" on long strings
  # NOTE -w sets the clipboard on the tmux client(s) using escape sequences
  printf '%s' "$1" | tmux load-buffer -w -
}

set_clipboard() {
  local text="$1"

  if is_termux && try_termux-clipboard "$text"
  then
    echo_success "clipboard set using termux-clipboard"
    return 0
  fi

  if is_wayland
  then
    echo_debug "Trying clipboard setter: wl-copy"
    if try_wl-copy "$text"
    then
      echo_success "clipboard set using wl-copy"
      return 0
    fi

    echo_debug "wl-copy failed."
    return 1
  fi

  # Xorg
  local methods=(kitty clipper xclip xsel osc52)
  for method in "${methods[@]}"
  do
    echo_debug "Trying clipboard setter: $method"
    if "try_${method}" "$text"
    then
      echo_success "clipboard set using $method"
      return 0
    fi
  done

  echo_error "All available clipboard setters have failed"
  exit 5
}

set_clipboard_file() {
  local filepath="$1"

  local MIMETYPE
  MIMETYPE="$(guess_mime_type "$filepath")"

  echo_debug "xcp mode: Set clipboard content from file (filepath=$filepath, type=$MIMETYPE)"

  if is_wayland
  then
    echo_debug "Trying clipboard setter: wl-copy"
    if try_wl-copy "$filepath"
    then
      echo_success "clipboard set using wl-copy"
      return 0
    fi

    echo_debug "wl-copy failed for binary content."
    return 1
  fi

  # Xorg
  echo_debug "Trying clipboard setter: xclip"
  if try_xclip "$filepath"
  then
    echo_success "clipboard set using xclip"
    return 0
  fi

  # last resort: osc52
  echo_debug "Trying clipboard setter: osc52"
  if try_osc52 "$(cat "$filepath")"
  then
    echo_success "clipboard set using osc52"
    return 0
  fi

  echo_error "No binary-capable clipboard backend found (need wl-copy or xclip)"
  return 5
}

schedule_clear_clipboard() {
  # TODO Clear tmux buffer?
  echo_debug "Scheduling deletion of value $1 in $TIMEOUT"

  (
    sleep "$TIMEOUT"

    og_content="$1"
    current_content="$(xcp --out --${SELECTION})"

    if [[ "${og_content}" == "${current_content}" ]]
    then
      "$0" "--${SELECTION}" <<< ''
    fi
  )&
  disown %1
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
  SELECTION=clipboard

  while [[ -n "$*" ]]
  do
    case "$1" in
      -d|-D|--debug)
        DEBUG=1
        shift
        ;;
      --trace)
        set -x
        shift
        ;;
      --notify|-n|-N)
        if [[ -n "$2" ]] && [[ ! "$2" =~ ^- ]]
        then
          # notify message (set by bw for eg)
          NOTIFY="$2"
          shift
        else
          NOTIFY=1
        fi
        shift
        ;;
      --icon|-I)
        NOTIFY_ICON="$2"
        shift 2
        ;;
      --no-clipper|--skip-clipper|-C)
        SKIP_CLIPPER=1
        shift
        ;;
      --both|-b)
        SELECTION=both
        shift
        ;;
      --primary|-p)
        SELECTION=primary
        shift
        ;;
      --secondary|-s)
        SELECTION=secondary
        shift
        ;;
      --out|-o)
        OUT=1
        shift
        ;;
      --in|-i)
        IN=1
        shift
        ;;
      --timeout|-t)
        TIMEOUT="$2"
        if [[ ! "$TIMEOUT" =~ ^[0-9]+$ ]]
        then
          echo "Invalid timeout value: $TIMEOUT" >&2
          exit 2
        fi
        shift 2
        ;;
      *)
        break
        shift
        ;;
    esac
  done

  echo_debug "DISPLAY=$DISPLAY WAYLAND_DISPLAY=$WAYLAND_DISPLAY"

  # input from terminal
  if [[ -n "$OUT" && -z "$IN" ]] || [[ -t 0 ]]
  then
    echo_debug "xcp mode: Get clipboard content"
    get_clipboard_content
    exit "$?"
  fi

  # input from pipe
  TMP="$(mktemp -t xcp.XXXXXX)"
  trap 'rm -f "$TMP"' EXIT
  cat > "$TMP"

  if stdin_is_binary "$TMP"
  then
    echo_debug "xcp mode: Set clipboard content from binary stdin"
    if [[ -n "$TIMEOUT" ]]
    then
      echo_debug "Ignoring --timeout for binary clipboard content"
    fi

    set_clipboard_file "$TMP"
    exit "$?"
  fi

  TEXT="$(cat "$TMP")"

  # Set tmux buffer
  set_tmux_buffer "$TEXT"

  echo_debug "xcp mode: Set clipboard content to \"$TEXT\""

  # Set clipboard content
  if ! set_clipboard "$TEXT"
  then
    echo_error "Failed to set clipboard, cannot schedule clear."
    exit 1
  fi

  if [[ -n $TIMEOUT ]]
  then
    schedule_clear_clipboard "$TEXT"
  fi

  exit 0
fi
