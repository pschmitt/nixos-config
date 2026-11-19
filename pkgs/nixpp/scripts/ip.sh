#!/usr/bin/env bash
# Nix defines nix_ip, android_network_command, and json_ip before this body.
# shellcheck disable=SC2154

android_query() {
  while [[ ${1:-} == -* ]]
  do
    case $1 in
      -4|-6|-o|-oneline) shift ;;
      *) return 1 ;;
    esac
  done

  case ${1:-} in
    r|ro|rou|rout|route)
      [[ ${2:-} == get ]] && return 0
      ;;
    a|ad|add|addr|addre|addres|address|l|li|lin|link|n|ne|nei|neig|neigh|neighbor|neighbour|ru|rul|rule)
      ;;
    *) return 1 ;;
  esac

  case ${2:-} in
    ''|s|sh|sho|show|l|li|lis|list) return 0 ;;
    *) return 1 ;;
  esac
}

main() {
  local -a query=()
  local json=0 shift_count=0
  local arg
  for arg in "$@"
  do
    case $arg in
      -j|-json|--json) json=1 ;;
      -d|-details|--details|-p|-pretty|--pretty) ;;
      -*) query+=("$arg") ;;
      *) break ;;
    esac
    shift_count=$((shift_count + 1))
  done
  query+=("${@:shift_count+1}")

  if (( json )) && android_query "${query[@]}"
  then
    exec "${json_ip[@]}" "$nix_ip" "${android_network_command[@]}" -- "$@"
  fi

  if ! android_query "$@"
  then
    exec "$nix_ip" "$@"
  fi

  local error result
  {
    if error=$(LC_ALL=C "$nix_ip" "$@" 2>&1 >&3)
    then
      [[ -z "$error" ]] || printf '%s\n' "$error" >&2
      return 0
    else
      result=$?
    fi
  } 3>&1

  case $error in
    'Cannot bind netlink socket: Permission denied'|'Cannot open netlink socket: Permission denied')
      ;;
    *)
      [[ -z "$error" ]] || printf '%s\n' "$error" >&2
      return "$result"
      ;;
  esac

  local command='exec /system/bin/ip'
  for arg in "$@"
  do
    # rish -c takes one shell program. Quote each argument for Android sh.
    arg=${arg//\'/\'\\\'\'}
    command+=" '$arg'"
  done
  if result=$("${android_network_command[@]}" "$command 2>&1")
  then
    printf '%s\n' "$result" | sed '1{/^Entering shell\.\.\.$/d;}'
  else
    local rc=$?
    printf '%s\n' "$result" | sed '1{/^Entering shell\.\.\.$/d;}' >&2
    return "$rc"
  fi
}

main "$@"

# vim: set ft=sh et ts=2 sw=2 :
