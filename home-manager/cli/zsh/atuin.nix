{
  config,
  lib,
  pkgs,
  osConfig ? null,
  ...
}:
let
  domain =
    if osConfig != null && osConfig ? domains && osConfig.domains ? main then
      osConfig.domains.main
    else if config ? domains && config.domains ? main then
      config.domains.main
    else
      null;
in
{
  assertions = [
    {
      assertion = domain != null;
      message = ''
        Unable to determine the main domain for Atuin.
        Define `domains.main` in the standalone Home Manager host module or run this config under NixOS-backed Home Manager.
      '';
    }
  ];

  programs.atuin = {
    enable = true;
    enableZshIntegration = false; # We manage this manually below
    forceOverwriteSettings = true;
    settings = {
      dialect = "uk";
      auto_sync = true;
      update_check = true;
      sync_address = "https://atuin.${domain}";
      sync_frequency = "15m";
      search_mode = "fuzzy";
    };
  };

  xdg.configFile."zsh/custom/os/nixos/system.zsh".text = lib.mkAfter ''
    # atuin
    source ${
      (pkgs.runCommand "atuin-init" { } ''
        mkdir -p $out/home
        HOME=$out/home ${pkgs.atuin}/bin/atuin init \
          --disable-ctrl-r \
          --disable-up-arrow \
          zsh > $out/init.zsh
        rm -rf $out/home
      '')
    }/init.zsh
    # bindkey '^[r' _atuin_search_widget
  '';
}
