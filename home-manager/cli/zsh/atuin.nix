{
  config,
  lib,
  pkgs,
  ...
}:
let
  domain = config.domains.main;
  termuxMode = config.termux.enable or false;
  termuxAtuin = pkgs.callPackage ../../../pkgs/termux-native/atuin.nix { };
  settings = {
    dialect = "uk";
    auto_sync = true;
    update_check = true;
    sync_address = "https://atuin.${domain}";
    sync_frequency = "15m";
    search_mode = "fuzzy";
  };
  atuinInitFile = pkgs.runCommand "atuin-init" { } ''
    mkdir -p $out/home
    HOME=$out/home ${pkgs.atuin}/bin/atuin init \
      --disable-ctrl-r \
      --disable-up-arrow \
      zsh > $out/init.zsh
    rm -rf $out/home
  '';
in
{
  programs.atuin = {
    enable = !termuxMode;
    enableZshIntegration = false; # We manage this manually below.
    forceOverwriteSettings = true;
    inherit settings;
  };

  home.packages = lib.optionals termuxMode [ termuxAtuin ];

  xdg.configFile = {
    "atuin/config.toml" = lib.mkIf termuxMode {
      source = (pkgs.formats.toml { }).generate "atuin-config" settings;
    };

    "zsh/custom/os/home-manager/system.zsh".text = lib.mkAfter (
      lib.optionalString (!termuxMode) ''
        # atuin
        source ${atuinInitFile}/init.zsh
        # bindkey '^[r' _atuin_search_widget
      ''
      + lib.optionalString termuxMode ''
        bindkey '^[r' _atuin_search_widget
      ''
    );
  };
}
