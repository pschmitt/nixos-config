#!/usr/bin/env bash

set -euo pipefail

# Ensure we are in the script's directory (repo root)
cd "$(cd "$(dirname "$0")" >/dev/null 2>&1; pwd -P)" || exit 9

HOSTNAME="${HOSTNAME:-$(hostname)}"

usage() {
  cat <<EOF
Usage: $(basename "$0") [COMMAND] [ARGS...]

Commands:
  repl [HOST]           Start Nix REPL for the given host (default: $HOSTNAME)
  eval [OPTS] ATTR      Evaluate a Nix attribute
  ATTR                  Shorthand for 'eval ATTR'

Options:
  -h, --help            Show this help message
  -H, --host HOST       Specify target host (default: $HOSTNAME)
  -m, --home-manager    Evaluate Home Manager configuration
  -r, --raw             Output raw string

Examples:
  $(basename "$0") repl
  $(basename "$0") repl x13
  $(basename "$0") eval --host x13 custom.username
  $(basename "$0") custom.username
  $(basename "$0") --home-manager wayland.windowManager.hyprland.settings
EOF
}

cmd_repl() {
  local host="${1:-$HOSTNAME}"
  # Simple help check for repl subcommand
  if [[ "$host" == "-h" || "$host" == "--help" ]]
  then
    usage
    exit 0
  fi
  nix --extra-experimental-features repl-flake repl ".#nixosConfigurations.$host"
}

cmd_eval() {
  local target_host="$HOSTNAME"
  local config_path
  local home_manager
  local jq_args=()
  local args=()

  while [[ $# -gt 0 ]]
  do
    case "$1" in
      -h|--help)
        usage
        exit 0
        ;;
      -r|--raw*)
        jq_args+=(-r)
        shift
        ;;
      -m|--home-manager|--homemanager|--hm)
        home_manager=1
        shift
        ;;
      -H|--host)
        if [[ -n "${2:-}" ]]
        then
          target_host="$2"
          shift 2
        else
          echo "Error: --host requires an argument" >&2
          exit 1
        fi
        ;;
      --)
        shift
        args+=("$@")
        break
        ;;
      *)
        args+=("$1")
        shift
        ;;
    esac
  done

  if [[ ${#args[@]} -eq 0 ]]
  then
    echo "Error: Missing attribute argument" >&2
    usage >&2
    exit 2
  elif [[ ${#args[@]} -gt 1 ]]
  then
    echo "Error: Too many arguments. Use --host to specify the host." >&2
    usage >&2
    exit 2
  fi

  config_path="config.${args[0]}"

  if [[ -n ${home_manager:-} ]]
  then
    config_path="\"home-manager\".users.${USER:-pschmitt}.${config_path}"
  fi

  echo "Evaluating attribute '${config_path}' for host '${target_host}'" >&2

  nix eval --json --no-warn-dirty --apply '
    n:
    let
      hp = n.pkgs.stdenv.hostPlatform;
    in {
      inherit (hp) system;
      res = n.'"${config_path}"';
    }
  ' ".#nixosConfigurations.${target_host}" | jq "${jq_args[@]}" '.res'
}

main() {
  if [[ $# -eq 0 ]]
  then
    usage
    exit 1
  fi

  case "$1" in
    repl|--repl)
      shift
      cmd_repl "$@"
      ;;
    eval)
      shift
      cmd_eval "$@"
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      # Pass everything to eval, it handles flags and args
      cmd_eval "$@"
      ;;
  esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
  main "$@"
fi
