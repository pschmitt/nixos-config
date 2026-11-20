#!/usr/bin/env bash

tmux_current_session_name() {
  # https://superuser.com/questions/410017/how-do-i-know-current-tmux-session-name-by-running-tmux-command

  tmux display-message -p '#S'

  # for s in $(tmux list-sessions -F '#{session_name}'); do
  #   tmux list-panes -F '#{pane_tty} #{session_name}' -t "$s"
  # done | grep "$(tty)" | awk '{print $2}'

  # local tty=$(tty)
  # for s in $(tmux list-sessions -F '#{session_name}' 2>/dev/null); do
  #     tmux list-panes -F '#{pane_tty} #{session_name}' -t "$s"
  # done | grep "$tty" | awk '{print $2}'

  # if [[ -n "$TMUX_PANE" ]]
  # then
  #   tmux list-panes -t "$TMUX_PANE" -F '#S' | head -n 1
  # fi
}

# echo "PARAMS: $@" >> /tmp/tmux.log

get_hostname() {
  local system_hostname
  system_hostname="$(hostname)"

  if [[ "$system_hostname" != "localhost" ]]
  then
    echo "$system_hostname"
    return
  fi

  # Use HOST var if set
  if [[ -n "$HOST" ]]
  then
    echo "$HOST"
    return 0
  fi

  # Use getprop on Termux
  if command -v termux-info >/dev/null
  then
    getprop net.hostname
    return
  fi

  # Default
  echo "$system_hostname"
}

status_left() {
  local halias
  local hcolor
  local scolor
  local session
  local shide

  # TMUX session
  local sname="$1"
  case "$sname" in
    main)
      shide=1
      ;;
    bg)
      scolor="#6c7570"
      ;;
    scratchpad)
      sname="📔"
      scolor="#035728"
      ;;
    *)
      scolor=red
      ;;
  esac

  # Hostname
  local host_name
  host_name="$(get_hostname)"

  local cust_file="${XDG_CONFIG_HOME:-$HOME/.config}/zsh/custom/hosts/${host_name}/zprompt"
  if [[ -r "$cust_file" ]]
  then
    # shellcheck disable=1090
    source "$cust_file"
  fi

  halias="${host_alias:-${host_name}}"

  # shellcheck disable=2154
  if [[ -n "$host_color" ]]
  then
    hcolor="colour${host_color}"
  else
    hcolor=red
  fi

  # TMUX session
  if [[ "$shide" != "1" ]]
  then
    session="#[fg=${scolor},bold]${sname} "
  fi

  # Hostname
  echo -n " $session#[fg=${hcolor}]"
  echo -n "$halias"
  echo " "
}

curl_cache() {
  "${HOME}/bin/curl-cache" "$@"
}

current_weather() {
  # NOTE
  # The first sed command removes the space after the weather icon
  # The second sed removes the '+' sign in front of positives temperatures
  # and the unit (°C)
  # FIXME 's/\+([0-9]+)°C/\1/' does not work on termux ("°" especially)
  res=$(curl_cache -c 300 -m 10 "wttr.in?m&format=%c%t")

  if [[ "$res" =~ ^"Unknown location".* ]]
  then
    echo "[tmux-status.sh] Error fetching weather: $res" >&2
    echo "😳wut?"
  else
    sed -r 's/(.) (.+)/\1\2/; s/\+([0-9]+).C/\1/' <<< "$res"
  fi
}

system_load() {
  uptime | sed -r 's/.*load average: (.+), (.+), (.+)/\1 \2 \3/; s/,/./g'
}

status_right() {
  local load

  load="$(system_load)"

  echo "${load}"

  # FIXME %H:%M:%S etc won't be expanded
  # echo "#[fg=red]Not implemented yet %H:%M:%S"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
  set -e

  case "$1" in
    --left|-l|left|L|-L)
      shift
      status_left "$*"
      ;;
    --right|-r|right|R|-R)
      shift
      status_right "$1"
      ;;
  esac
fi
