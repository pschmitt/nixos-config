#!/usr/bin/env bash

version_at_least() {
  local current="$1"
  local desired="$2"
  local max

  max="$(echo -e "${current}\n${desired}" |
         sort --version-sort | head -1)"

  [[ "$max" == "$current" ]]
}

tmux_get_version() {
  # https://stackoverflow.com/q/26705755/1872036
  local tmux_version
  local strip_prefix

  case "$1" in
    -s|--strip|--short)
      strip_prefix=1
      ;;
  esac

  # tmux 3.2 exports TERM_PROGRAM and TERM_PROGRAM_VERSION
  # shellcheck disable=2153
  if [[ "$TERM_PROGRAM" == "tmux" ]] && [[ -n "$TERM_PROGRAM_VERSION" ]]
  then
    tmux_version="$TERM_PROGRAM_VERSION"
  # This is only set by out own config
  elif [[ -n "$TMUX_VERSION" ]]
  then
    tmux_version="$TMUX_VERSION"
  elif [[ -n "$TMUX" ]]
  then
    tmux_version="$("$(realpath /proc/"$(tmux display-message -p "#{pid}")"/exe)" -V |
                    sed -rn 's/^tmux ([^\s]+).*/\1/p')"
    if [[ -z "$tmux_version" ]]
    then
      # Get server version
      # This is not necessarily what we want since one could update tmux
      # while having a tmux server running, but this should be the same in
      # most cases
      tmux_version="$(tmux display-message -p "#{version}")"
    fi
  else
    # Outside of tmux
    tmux_version="$(command tmux -V 2>/dev/null |
                    sed -rn 's/^tmux ([^\s]+).*/\1/p')"
  fi

  if [[ -n "$strip_prefix" ]]
  then
    echo "${tmux_version##next-}"
  else
    echo "$tmux_version"
  fi
}

tmux_at_least() {
  version_at_least "$1" "$(tmux_get_version --short)"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
  case "$1" in
    at-least|atleast|atl|gt)
      shift
      tmux_at_least "$@"
      ;;
    export|set)
      # tmux-version.sh export can have an argument that will be used as the
      # version.
      # Example invokation:
      # run-shell "$TMUX_BIN_HOME/tmux-version.sh export #{version}"
      tmux setenv -g TMUX_VERSION "${2:-$(tmux_get_version)}"
      ;;
    *)
      tmux_get_version "$@"
      ;;
  esac

fi
