# wofi-menu — Nix-native port of the tractable subset of the zhj-backed
# ~/bin/wofi.zsh launcher: the run, emoji and soundboard menus. The
# bitwarden / misc / meetings menus still live in wofi.zsh because their
# backends (bww/rbw, banking, jcal) are not ported yet.

usage() {
  echo "Usage: wofi-menu {run|emoji|soundboard [stop]}" >&2
}

# Close any open wofi first (so a second keypress toggles it shut), like the
# original did before dispatching.
kill_wofi() {
  { killall wofi; killall .wofi-wrapped; } >/dev/null 2>&1 || true
}

run_menu() {
  local cmd
  cmd="$(wofi --insensitive --show=drun --prompt="󰜎 Run" --define=drun-print_command=true)"

  if [[ -z "$cmd" ]]
  then
    echo "No command selected" >&2
    exit 1
  fi

  # DIRTYFIX (from the original): force the GTK theme for launched apps.
  local theme
  theme="$(gsettings get org.gnome.desktop.interface gtk-theme 2>/dev/null | tr -d "'\"")"

  notify-send -a "wofi-run" "󰜎 Launching \"$cmd\""

  # Launch detached so the app survives this process exiting. Inherits the
  # session env (WAYLAND_DISPLAY etc) from the keybind that invoked us.
  if [[ -n "$theme" ]]
  then
    setsid -f sh -c "GTK_THEME=$theme $cmd"
  else
    setsid -f sh -c "$cmd"
  fi
}

emoji_menu() {
  local emoji
  emoji="$(emoji-fzf --custom-aliases "$HOME/.config/emoji-fzf/emojis.json" preview --prepend \
    | sed -r 's/&/&amp;/g; s/_/ /g; s/^(\S+)\s+(.+)$/\1 <span foreground="gray">\2<\/span>/' \
    | wofi --show dmenu \
        --insensitive \
        --matching fuzzy \
        --allow-markup \
        --prompt "🎩 Emoji selection lol" \
    | awk '{print $1}' | tr -d '\n')"

  if [[ -z "$emoji" ]]
  then
    echo "No emoji selected" >&2
    return 1
  fi

  printf '%s' "$emoji" | wl-copy
  notify-send -a "wofi-emoji" "📋 Copied $emoji to clipboard"
}

soundboard_menu() {
  local -a sounds
  mapfile -t sounds < <(soundboard list)

  local res
  res="$(printf '%s\n' "${sounds[@]}" \
    | wofi --dmenu -p "🎹 What are we playing?" -l "${#sounds[@]}" -i)"

  [[ -z "$res" ]] && return 1

  soundboard play "$res"
}

kill_wofi

case "${1:-}" in
  run)
    shift
    run_menu
    ;;
  emoji | emoj* | e)
    emoji_menu
    ;;
  soundboard | sb)
    case "${2:-}" in
      stop | halt | end | pause)
        notify-send -t 1000 "🎹 Stopping soundboard playback..."
        soundboard stop
        ;;
      *)
        soundboard_menu
        ;;
    esac
    ;;
  -h | --help | help | "")
    usage
    [[ "${1:-}" == "" ]] && exit 2 || exit 0
    ;;
  *)
    echo "Unknown action: \"$1\"" >&2
    usage
    exit 2
    ;;
esac
