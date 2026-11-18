#!/system/bin/sh

# This file is sourced by session.sh, which owns and uses these variables.
# shellcheck disable=SC2034,SC2154
load_system_candidate() {
  candidate_name=$2
  case $candidate_name in
    ''|.*|*[!a-zA-Z0-9._+-]*)
      printf 'Invalid system candidate name.\n' >&2
      return 1
      ;;
  esac
  candidate_directory="$1/system-candidates/$candidate_name"
  if [[ -L "$1/system-candidates" || -L "$candidate_directory" || -L "$candidate_directory/etc" || -L "$candidate_directory/session" || ! -f "$candidate_directory/session" || ! -d "$candidate_directory/etc" ]]
  then
    printf 'System candidate is missing or has an unsupported directory link.\n' >&2
    return 1
  fi
  if ! {
    IFS= read -r candidate_user &&
    IFS= read -r candidate_home &&
    IFS= read -r candidate_path &&
    IFS= read -r candidate_shell &&
    IFS= read -r candidate_certificate &&
    IFS= read -r candidate_terminfo &&
    {
      ! IFS= read -r candidate_extra && [[ -z $candidate_extra ]]
    }
  } < "$candidate_directory/session"
  then
    printf 'Invalid system candidate session descriptor.\n' >&2
    return 1
  fi
  if [[ $candidate_user != "$session_user" || $candidate_home != "$session_home" ]]
  then
    printf 'System candidate identity does not match the runtime.\n' >&2
    return 1
  fi
  for candidate_value in "$candidate_path" "$candidate_shell" "$candidate_certificate" "$candidate_terminfo"
  do
    case $candidate_value in
      /nix/store/*)
        candidate_store_item=${candidate_value#/nix/store/}
        candidate_hash=${candidate_store_item%%-*}
        if [[ ${#candidate_hash} != 32 ]]
        then
          printf 'Invalid system candidate store hash.\n' >&2
          return 1
        fi
        case $candidate_hash in
          *[!a-z0-9]*)
            printf 'Invalid system candidate store hash.\n' >&2
            return 1
            ;;
        esac
        case $candidate_store_item in
          ''|*[!a-zA-Z0-9+._/-]*|../*|*/../*|*/..)
            printf 'Invalid system candidate store path.\n' >&2
            return 1
            ;;
        esac
        ;;
      *)
        printf 'System candidate paths must be store-backed.\n' >&2
        return 1
        ;;
    esac
  done
  SESSION_PATH=$candidate_path
  SESSION_SHELL=$candidate_shell
  SESSION_CERTIFICATE=$candidate_certificate
  SESSION_TERMINFO=$candidate_terminfo
  session_etc="$candidate_directory/etc"
}

# vim: set ft=sh et ts=2 sw=2 :
