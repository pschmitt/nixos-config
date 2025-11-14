#!/usr/bin/env bash

hyprctl() {
  echo -e "\e[95m🚀 Running 'hyprctl $*'\e[0m" >&2
  command hyprctl "$@"
}

find_windows() {
  local class="$1"
  hyprctl -j clients | \
    jq -er --arg class "$class" '[.[] | select(.class  == $class)]'
}

current_workspace() {
  hyprctl -j activeworkspace
}

window_addrs() {
  jq -er '.[].address'
}

is_hidden() {
  jq -er '.[].workspace.name | test("^special")' >/dev/null
}

is_floating() {
  jq -er 'all(.[]; .floating == true)' >/dev/null
}

array_join() {
  local IFS="$1"
  shift
  echo "$*"
}

slugify() {
  iconv -t ascii//TRANSLIT <<< "$*" | \
    sed -r -e 's/[^[:alnum:]]+/-/g' -e 's/^-+|-+$//g' | \
    tr '[:upper:]' '[:lower:]'
}

gtk_theme() {
  zhj theme::current
}

toggle_scratchpad() {
  local class
  local cmd
  local position
  local width height
  local force_size
  local alpha

  while [[ -n "$*" ]]
  do
    case "$1" in
      -c|--class)
        class="$2"
        shift 2
        ;;
      -C|--center)
        center=1
        shift
        ;;
      -p|--position)
        position="$2"
        shift 2
        ;;
      -w|--width)
        width="$2"
        shift 2
        ;;
      -h|--height)
        height="$2"
        shift 2
        ;;
      -f|--force*)
        force_size=1
        shift
        ;;
      -a|--alpha)
        alpha="$2"
        shift 2
        ;;
      *)
        break
        ;;
    esac
  done

  cmd=("$@")

  if [[ -z "${cmd[*]}" ]]
  then
    echo "Error: No command specified..." >&2
    return 2
  fi

  # Default to class = cmd
  if [[ -z "$class" ]]
  then
    # default to first word
    class="${cmd[0]}"
    # Extract class from "env X=1 Y=2 CMD" cmds
    if [[ "$class" == env ]]
    then
      for word in "${CMD[@]}"
      do
        if [[ ! "$word" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]]
        then
          class="$word"
          break
        fi
      done
    fi
  fi

  local window_data
  window_data="$(find_windows "$class")"

  local -a extra_args
  local -a batch
  local batch_str

  if jq -er 'length == 0' <<< "$window_data" >/dev/null
  then
    # No window found, spawn cmd
    local rules=(float noanim)

    if [[ -n "$width" && -n "$height" ]]
    then
      rules+=("size $width $height")
    fi

    if [[ -n "$center" ]]
    then
      rules+=(center)
      # batch+=("; dispatch centerwindow")
      # batch=(dispatch centerwindow)
    fi

    if [[ -n "$alpha" ]]
    then
      rules+=("opacity $alpha")
    fi

    local rules_str
    rules_str="$(array_join ';' "${rules[@]}")"

    # --batch does not work with exec rules
    # https://github.com/hyprwm/Hyprland/issues/1820
    # hyprctl --batch "dispatch exec [${rules_str}] ${cmd}${batch[*]}"
    hyprctl dispatch exec -- "[${rules_str}] ${cmd[*]@Q}"
    local rc="$?"

    if [[ -n "${batch[*]}" ]]
    then
      batch_str="$(array_join ';' "${batch[@]}")"
      hyprctl --batch "$batch_str"
    fi

    if [[ "$rc" -eq 0 ]]
    then
      for _ in {1..50}
      do
        [[ -n "$center" ]] && extra_args+=(--center)
        [[ -n "$position" ]] && extra_args+=(--position "$position")

        if ~/.config/hypr/bin/resize-window.sh \
          --width "${width}" --height "${height}" "${extra_args[@]}" "$class"
        then
          break
        fi

        echo "Retrying to resize window $class..." >&2

        sleep 0.1
      done
    fi

    return "$rc"
  fi

  local addr
  local win_addrs
  mapfile -t win_addrs <<< "$(window_addrs <<< "$window_data")"

  if ! is_floating <<< "$window_data"
  then
    for addr in "${win_addrs[@]}"
    do
      echo "Setting window $addr to floating"
      hyprctl dispatch togglefloating "address:$addr"
    done
  fi

  if ! is_hidden <<< "$window_data"
  then
    for addr in "${win_addrs[@]}"
    do
      echo "Hiding windows of class '$class' (addr: $addr)"
      hyprctl dispatch movetoworkspacesilent "special,address:$addr"
    done
    return "$?"
  fi

  echo "Bringing window to current WS"

  local current_ws
  current_ws="$(current_workspace | jq -er .id)"

  # NOTE How about using the class instead of the address?
  # This would probably move the dialogs as well.
  # hyprctl dispatch movetoworkspace "${current_ws},address:${window_addr}"

  for addr in "${win_addrs[@]}"
  do
    batch+=("dispatch movetoworkspace ${current_ws},address:${addr}")
  done

  if [[ -n "$center" ]]
  then
    batch+=("dispatch centerwindow")
  fi

  if [[ -n "$alpha" ]]
  then
    # https://wiki.hyprland.org/Configuring/Using-hyprctl/#setprop
    batch+=("setprop $class alpha ${alpha}")
  fi

  local batch_str
  batch_str="$(array_join ';' "${batch[@]}")"
  hyprctl --batch "$batch_str"

  if [[ -z "$force_size" || -z "$width" || -z "$height" ]]
  then
    return
  fi

  # NOTE We need to resize *after* moving the scratchpad window, otherwise
  # resize-window.sh might use the wrong monitor dimensions.
  [[ -n "$center" ]] && extra_args+=(--center)
  [[ -n "$position" ]] && extra_args+=(--position "$position")

  ~/.config/hypr/bin/resize-window.sh \
    --width "${width}" --height "${height}" "${extra_args[@]}" "$class"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
  # HACK Below forces natilus to use the default gtk theme, for some unknown
  # reason nautilus just doesn't it by default on ge2 (nixos)
  DEFAULT_GTK_THEME="$(gtk_theme)"
  GTK_APP_CMD=(env GTK_THEME="$DEFAULT_GTK_THEME")

  if [[ -z "$1" ]]
  then
    echo "Missing scratchpad name (eg: $0 term or $0 files)" >&2
    exit 2
  fi

  case "$1" in
    files|nautilus)
      CMD=("${GTK_APP_CMD[@]}" nautilus)
      CLASS=org.gnome.Nautilus

      toggle_scratchpad \
        --class "$CLASS" \
        --center \
        --width 66% \
        --height 66% \
        --force \
        "${CMD[@]}"
      ;;
    audio|pavucontrol)
      CMD=("${GTK_APP_CMD[@]}" pavucontrol)
      CLASS=org.pulseaudio.pavucontrol

      toggle_scratchpad --class "$CLASS" --center "${CMD[@]}"
      ;;
    kitty|term*)
      CLASS=kitty-scratchpad
      CMD=(
        env SCRATCHPAD=1 TMUX_TMPDIR=/run/user/1000
        kitty
        --class "$CLASS"
        --
        tmux -f "$HOME/.config/tmux/tmux.conf" -u new -A -D -s scratchpad zsh
      )

      toggle_scratchpad \
        --class "$CLASS" \
        --alpha 1.0 \
        --position center-top \
        --width 70% \
        --height 50% \
        --force \
        "${CMD[@]}"
      ;;
    wezt*)
      CLASS=wezterm-scratchpad
      CMD=(
        env SCRATCHPAD=1
        wezterm start --always-new-process
        --class "$CLASS"
        --
        tmux -f "$HOME/.config/tmux/tmux.conf" -u new -A -D -s scratchpad zsh
      )

      toggle_scratchpad \
        --class "$CLASS" \
        --alpha 1.0 \
        --position center-top \
        --width 70% \
        --height 50% \
        --force \
        "${CMD[@]}"
      ;;
    foot*)
      CLASS=foot-scratchpad
      # NOTE We cannot use footclient since it does not support --config
      CMD=(
        env SCRATCHPAD=1 foot
        --config="${XDG_CONFIG_HOME:-${HOME}/.config}/foot/scratchpad.ini"
        --app-id "$CLASS"
        tmux -f "$HOME/.config/tmux/tmux.conf" -u new -A -D -s scratchpad zsh
      )

      toggle_scratchpad \
        --class "$CLASS" \
        --alpha 1.0 \
        --position center-top \
        --width 70% \
        --height 50% \
        --force \
        "${CMD[@]}"
      ;;
    cal*)
      CLASS=term_calendar
      CMD=(foot --app-id "$CLASS" sh -c 'cal -y; read -s -n 1')
      toggle_scratchpad \
        --class "$CLASS" \
        --width 45% \
        --height 80% \
        --position center \
        "${CMD[@]}"
      ;;
    sound*)
      CLASS=Soundux
      CMD=(flatpak run io.github.Soundux)
      toggle_scratchpad \
        --class "$CLASS" \
        --width 45% \
        --height 80% \
        --position center \
        "${CMD[@]}"
      ;;
    *)
      echo "Unknown scratchpad: '$1'" >&2
      exit 2
      ;;
  esac
fi
