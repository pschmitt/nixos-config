{
  lib,
  pkgs,
  ...
}:
{
  home.packages = with pkgs; [
    atuin
  ];

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
