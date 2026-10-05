{
  config,
  lib,
  pkgs,
  ...
}:
let
  domain = config.domains.main;
  termuxMode = config.termux.enable or false;
  settings = {
    dialect = "uk";
    auto_sync = true;
    update_check = true;
    sync_address = "https://atuin.${domain}";
    sync_frequency = "15m";
    search_mode = "fuzzy";
  };
in
{
  programs.atuin = {
    enable = !termuxMode;
    enableZshIntegration = false; # We manage this manually below
    forceOverwriteSettings = true;
    inherit settings;
  };

  termux.packages = lib.mkIf termuxMode [ "atuin" ];

  xdg.configFile = {
    "atuin/config.toml" = lib.mkIf termuxMode {
      source = (pkgs.formats.toml { }).generate "atuin-config" settings;
    };
    "zsh/custom/os/home-manager/system.zsh".text = lib.mkAfter (
      if termuxMode then
        ''
          # atuin
          eval "$(atuin init --disable-ctrl-r --disable-up-arrow zsh)"
          # bindkey '^[r' _atuin_search_widget
        ''
      else
        ''
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
        ''
    );
  };
}
