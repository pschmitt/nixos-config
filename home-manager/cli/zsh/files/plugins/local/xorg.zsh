# Xorg

# Wake screen and disable screensaver
# alias son="xdspv; xdotool key ctrl; xset dpms force on; xset -dpms; xset s off"

alias xdspv="xorg::export-display"

# xsel magic
if (( $+commands[xsel] ))
then
  alias bx="xsel -b | xsel"
  alias xb="xsel | xsel -b"
fi

if (( $+commands[xhost] ))
then
  xhost::allow-root() {
    xhost si:localuser:root
  }

  xhost::disallow-root() {
    xhost -si:localuser:root
  }
fi

if (( $+commands[xrandr] ))
then
  xrdr::displays() {
    xrandr --listmonitors | awk '/^\s*[0-9]+:\s*/ { print $NF }'
  }

  xrdr::main-display() {
    xrdr::displays | grep -m 1 -Ei 'eDP|lvds'
  }

  xrdr::ext-display() {
    xrdr::displays | grep -m 1 -Eiv 'eDP|lvds'
  }

  xrdr() {
    local usage="Usage: $0 left|right|above|below"

    case "$1" in
      help|h|-h|--help)
        echo "$usage"
        return
        ;;
      right|left|above|below|up|down|l|r|u|d|a|b)
        local main=$(xrdr::main-display)
        local ext=$(xrdr::ext-display)

        local dir

        case "$1" in
          r|right)
            dir="right-of"
            ;;
          l|left)
            dir="left-of"
            ;;
          above|ab|a|up|u)
            dir="above"
            ;;
          below|down|under|d)
            dir="below"
            ;;
        esac

        if [[ -z "$main" ]]
        then
          echo_err "Failed to determine main display"
          return 1
        fi

        if [[ -z "$ext" ]]
        then
          echo_err "Failed to determine external display"
          return 1
        fi

        xrandr --output "$ext" "--${dir}" "$main"
        ;;
      *)
        echo "$usage" >&2
        return 2
        ;;
    esac
  }
fi

# if (( $+commands[xrdr] )) && [[ -z "$NO_COMPLETIONS" ]]
# then
#   compctl -k "(count debug primary secondary tertiary toggle extend copy)" xrdr
# fi

if (( $+commands[Xephyr] ))
then
  xephyr::start() {
    local display="${1:-:1}"
    Xephyr -br -ac -noreset -screen 1280x720 :1 >/dev/null 2>&1
  }

  xephyr::startx() {
    local display=:1
    local cmd
    local wm

    case "$1" in
      qtile)
        wm=qtile
        cmd=(qtile start)
        ;;
      *)
        cmd=($@)
        ;;
    esac

    if [[ -z "$cmd" ]]
    then
      echo_err "Missing command"
      return 2
    fi

    xephyr::start "$display" &

    DISPLAY=$display $cmd[@]

    # Kill WM
    if [[ -n "$wm" ]]
    then
      pkill -9 $wm
    fi

    # Kill backgrounded Xephyr
    pkill -9 Xephyr
  }

  # FIXME Why is this so much slower than xephyr::startx?!
  xephyr::startx-slow() {
    local usage="Usage: $0 CMD"
    local help

    if [[ -z "$1" ]]
    then
      echo "$usage" >&2
      return 2
    fi

    zparseopts -D -E \
      h=help -help=help

    if [[ -n "$help" ]]
    then
      echo "$usage"
      return
    fi

    local display=:1
    local resolution=1280x720
    local cmd
    local wm
    local logfile

    case "$1" in
      qtile)
        wm=qtile
        logfile=${XDG_DATA_HOME}/qtile/qtile.log
        cmd=(qtile start)
        ;;
      *)
        cmd=($@)
        ;;
    esac

    if [[ -z "$cmd" ]]
    then
      echo_err "Missing command"
      echo "$usage" >&2
      return 2
    fi

    local xinitrc=$(mktemp)
    local cmd_xephyr=$(mktemp)

    trap "rm -f '$xinitrc' '$cmd_xephyr'" EXIT INT

    # Create temporary xinitrc
    echo -e "echo 'Launching $cmd'>&2\nexec $cmd[@]" >! "$xinitrc"

    # Create xephyr start script with parameter
    cat <<EOF >! $cmd_xephyr
#!/usr/bin/env bash
Xephyr -br -ac -noreset -screen ${resolution} ${display} >/dev/null 2>&1
EOF
  chmod +x "$cmd_xephyr"

  # FIXME Why can't we set the screensize here below?
  # The X server starts with the correct size but it then exits immediately
  xinit "$xinitrc" -- "$cmd_xephyr" "$display"
  }
fi
