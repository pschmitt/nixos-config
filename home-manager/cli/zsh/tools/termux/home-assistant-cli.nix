{
  config,
  inputs,
  pkgs,
  ...
}:
let
  termuxMode = config.termux.enable or false;
  termuxPackageSet = import ../../../../../pkgs/termux/native/package-set.nix {
    inherit inputs pkgs;
  };
  hassCli =
    if termuxMode then termuxPackageSet.termuxPackages.home-assistant-cli else pkgs.home-assistant-cli;
  completions = pkgs.runCommand "home-assistant-cli-zsh-completions" { } ''
    mkdir -p "$out"
    _HASS_CLI_COMPLETE=zsh_source ${pkgs.buildPackages.home-assistant-cli}/bin/hass-cli completion zsh > "$out/_hass-cli"
  '';
in
{
  home.packages = [ hassCli ];
  xdg.configFile."zsh/completions/_hass-cli".source = "${completions}/_hass-cli";
}
