{
  lib,
  osConfig,
  pkgs,
  ...
}:
{
  programs.atuin = {
    enable = true;
    enableZshIntegration = false; # We manage this manually below
    settings = {
      dialect = "uk";
      auto_sync = true;
      update_check = true;
      sync_address = "https://atuin.${osConfig.domains.main}";
      sync_frequency = "1h";
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
