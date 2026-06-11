{ pkgs, ... }:
{
  environment.systemPackages = [
    # https://mullvad.net/en/check
    (pkgs.writeShellApplication {
      name = "am-i-mullvad";
      runtimeInputs = with pkgs; [
        curl
        jq
      ];
      text = builtins.readFile ./scripts/am-i-mullvad.sh;
    })

    # Alias: mullvad-status
    (pkgs.writeShellScriptBin "mullvad-status" ''
      am-i-mullvad "$@"
    '')
  ];
}
