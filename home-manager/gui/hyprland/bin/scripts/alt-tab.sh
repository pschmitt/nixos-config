#!/usr/bin/env bash

SELF=$(realpath "${BASH_SOURCE[*]}")
PREVIEW_FILE=${TMPDIR:-/tmp}/hyprland-alttab-preview.png

usage() {
  echo "Usage: $(basename "$0") enable|disable|preview [ARGS]"
}

alttab_enable() {
  hyprctl -q --batch "keyword animations:enabled false ; dispatch exec foot --app-id alttab '$SELF' '$1' ; keyword unbind ALT, TAB ; keyword unbind ALT SHIFT, TAB ; dispatch submap alttab"
}

alttab_disable() {
  hyprctl -q keyword animations:enabled true

  hyprctl -q --batch "keyword unbind ALT, TAB ; keyword unbind ALT SHIFT, TAB ; keyword bind ALT, TAB, exec, '$SELF' enable 'down' ; keyword bind ALT SHIFT, TAB, exec, '$SELF' enable 'up'"
}

apply_preview_transform() {
  local transform="$1"

  local mogrify_bin
  mogrify_bin="$(command -v mogrify 2>/dev/null)"

  if [[ -z "$mogrify_bin" ]]
  then
    echo "mogrify not found, skipping preview transform" >&2
    return 0
  fi

  local -a args=()
  case "$transform" in
    ""|0|null)
      return 0
      ;;
    1)
      args=(-rotate 90)
      ;;
    2)
      args=(-rotate 180)
      ;;
    3)
      args=(-rotate 270)
      ;;
    4)
      args=(-flop)
      ;;
    5)
      args=(-transpose)
      ;;
    6)
      args=(-flip)
      ;;
    7)
      args=(-transverse)
      ;;
    *)
      return 0
      ;;
  esac

  "$mogrify_bin" "${args[@]}" "$PREVIEW_FILE"
}

alttab_preview() {
  local addr="$1" transform="${2:-0}" dim

  dim=${FZF_PREVIEW_COLUMNS}x${FZF_PREVIEW_LINES}

  grim-hyprland -t png -l 0 -w "$addr" "$PREVIEW_FILE" || return 1
  apply_preview_transform "$transform"
  chafa --animate false -s "$dim" "$PREVIEW_FILE"
}

alttab_fzf() {
  local start="$1" monitors_json="[]"
  local address

  if ! monitors_json="$(hyprctl -j monitors 2>/dev/null)"
  then
    monitors_json="[]"
  fi

  # shellcheck disable=SC2064
  trap "rm -rf '$PREVIEW_FILE'" EXIT

  address=$(hyprctl -j clients | \
      jq -er --argjson monitors "$monitors_json" '
        sort_by(.focusHistoryID)
        | .[]
        | select(.workspace.id >= 0)
        | (.monitor // -1) as $monID
        | (($monitors[] | select(.id == $monID) | .transform) // 0) as $transform
        | "\(.address)\t\(.title)\t\($transform)"
      ' |
      fzf \
        --cycle \
        --sync \
        --bind "tab:down,shift-tab:up,start:${start},double-click:ignore" \
        --wrap \
        --delimiter=$'\t' \
        --with-nth=2 \
        --preview "'$SELF' preview {1} {3}" \
        --preview-window=right:80% \
        --layout=reverse |
      awk -F"\t" '{print $1}')

  if [[ -n "$address" ]]
  then
    hyprctl --batch -q "dispatch focuswindow address:${address} ; dispatch alterzorder top"
  fi

  hyprctl -q dispatch submap reset
}

main() {
  local action="fzf" # default action

  case "$1" in
    -h|--help|-\?|help)
      usage
      return 0
      ;;
    enable|on)
      action=enable
      shift
      ;;
    disable|off)
      action=disable
      shift
      ;;
    *preview*)
      action=fzf-preview
      shift
      ;;
    *fzf*)
      action=fzf
      shift
      ;;
  esac

  case "$action" in
    help)
      usage
      ;;
    enable)
      alttab_enable "$@"
      ;;
    disable)
      alttab_disable "$@"
      ;;
    fzf)
      alttab_fzf "$@"
      ;;
    fzf-preview)
      alttab_preview "$@"
      ;;
    *)
      echo "Unknown action: $action" >&2
      usage >&2
      return 2
      ;;
  esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
  main "$@"
fi
