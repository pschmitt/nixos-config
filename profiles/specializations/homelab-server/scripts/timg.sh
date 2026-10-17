# Wrapped by writeShellApplication: shebang and `set -euo pipefail` are injected
# by Nix.

main() {
  local arg
  local pixelation_set=

  for arg in "$@"
  do
    case "$arg" in
      -p|-p?*|--pixelation|--pixelation=*)
        pixelation_set=1
        break
        ;;
    esac
  done

  if [[ -n "$pixelation_set" ]]
  then
    exec "@TIMG_BIN@" "$@"
  fi

  exec "@TIMG_BIN@" -pk "$@"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
  main "$@"
fi

# vim: set ft=sh et ts=2 sw=2 :
