notify() {
  local category="$1"
  shift

  local extra_args=()
  if [[ -n $NOTIFICATION_ID ]]
  then
    extra_args+=("--replace-id=${NOTIFICATION_ID}")
  else
    extra_args+=(--print-id)
  fi

  local icon_path=${XDG_PICTURES_DIR:-${HOME}/Pictures}/Icons/mako
  NOTIFICATION_ID=$(notify-send \
    --app-name="$0" \
    --category="$category" \
    --icon="${icon_path}/${category}.png" \
    "${extra_args[@]}" \
    "$@")
}

notify_info() { notify info "$@"; }
notify_error() { notify error "$@"; }
notify_success() { notify success "$@"; }
