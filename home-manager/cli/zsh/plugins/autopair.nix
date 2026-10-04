{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (import ./path.nix { inherit config lib; }) pluginPath;
in
{
  programs.zsh.initContent = lib.mkOrder 950 ''
    if zsh::prompt-plugins-enabled && not_in_vt
    then
      zsh::source-plugin ${
        pluginPath "autopair" "autopair.zsh" "${pkgs.zsh-autopair}/share/zsh/zsh-autopair/autopair.zsh"
      }
      bindkey -- '^H' backward-kill-word
    fi
  '';
}
