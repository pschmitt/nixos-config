#!/usr/bin/env bash

# Keep flags that Android's ip can represent. In particular, Android ip can
# ignore -j and print text, so never use it to answer a JSON request.
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

  local arg command=/system/bin/ip
  for arg in "$@"
  do
    # rish -c takes one shell program. Quote each argument for Android sh.
    arg=${arg//\'/\'\\\'\'}
    command+=" '$arg'"
  done
  "$shizuku_rish" -c "$command" | sed '1{/^Entering shell\.\.\.$/d;}'
}

main "$@"

# vim: set ft=sh et ts=2 sw=2 :
