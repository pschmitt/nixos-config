{ pkgs, ... }:
{
  environment.systemPackages = [
    # https://mullvad.net/en/check
    (pkgs.writeShellScriptBin "am-i-mullvad" ''
      URL=https://am.i.mullvad.net
      JSON=""

      case "$1" in
        -j|--json)
          shift
          URL+="/json"
          JSON=1
          ;;
        *)
          URL+="/connected"
          ;;
      esac

      ${pkgs.curl}/bin/curl -fsSL "$URL" "$@" | {
        if [[ -z "$JSON" ]]
        then
          cat
        else
          ${pkgs.jq}/bin/jq '.'
        fi
      }
    '')
  ];
}
