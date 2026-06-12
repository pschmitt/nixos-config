#!/usr/bin/env bash
# Relative mouse move / click via dotool. Replaces the zhj mouse::move and
# mouse::click keybind helpers.
#
#   mouse-ctl.sh move [-y] PIXELS [PIXELS_Y]
#   mouse-ctl.sh click [BUTTON]

cmd="${1:-}"
shift || true

case "$cmd" in
  move)
    y=
    if [[ "${1:-}" == "-y" ]]
    then
      y=1
      shift
    fi

    px1="${1:-}"
    px2="${2:-}"
    if [[ ! "$px1" =~ ^[-+]?[0-9]+$ ]]
    then
      echo "usage: mouse-ctl.sh move [-y] PIXELS [PIXELS_Y]" >&2
      exit 2
    fi

    if [[ -n "$px2" ]]
    then
      px_x="$px1"
      px_y="$px2"
    elif [[ -n "$y" ]]
    then
      px_x=0
      px_y="$px1"
    else
      px_x="$px1"
      px_y=0
    fi

    # dotool expects coordinates at 2x the actual pixel delta.
    dotoolc <<< "mousemove $((px_x * 2)) $((px_y * 2))"
    ;;
  click)
    dotoolc <<< "click ${1:-left}"
    ;;
  *)
    echo "usage: mouse-ctl.sh {move [-y] PIXELS [PIXELS_Y]|click [BUTTON]}" >&2
    exit 2
    ;;
esac
