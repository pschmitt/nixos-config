{ pkgs, ... }:
let
  completions = pkgs.runCommand "home-assistant-cli-zsh-completions" { } ''
    mkdir -p "$out"
    _HASS_CLI_COMPLETE=zsh_source ${pkgs.buildPackages.home-assistant-cli}/bin/hass-cli completion zsh > "$out/_hass-cli"
  '';
in
{
  home.packages = [ pkgs.home-assistant-cli ];
  xdg.configFile."zsh/completions/_hass-cli".source = "${completions}/_hass-cli";
}
