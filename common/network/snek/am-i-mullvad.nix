{ pkgs, ... }:
{
  environment.systemPackages = [
    # https://mullvad.net/en/check
    (pkgs.writeShellScriptBin "am-i-mullvad" ''
      URL=https://am.i.mullvad.net

      case "$1" in
        -j|--json)
          shift
          URL+="/json"
          ;;
        *)
          URL+="/connected"
          ;;
      esac

      exec ${pkgs.curl}/bin/curl -fsSL "$URL"
    '')
  ];
}
