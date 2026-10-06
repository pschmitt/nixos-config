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
        # Atuin shares this timestamp between its preexec and precmd hooks.
        typeset -g __atuin_preexec_time
        source "$TERMUX_GENERATION/home/.config/zsh/termux/atuin-init.zsh"
        bindkey '^[r' _atuin_search_widget
      ''
    );
  };

  xdg.configFile."zsh/termux/atuin-init.zsh" = lib.mkIf termuxMode {
    source = "${atuinInitFile}/init.zsh";
  };
}
