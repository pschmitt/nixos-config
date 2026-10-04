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
  programs.zsh.initContent = lib.mkOrder 1120 ''
    zsh::source-plugin ${
      pluginPath "oh-my-zsh" "lib/spectrum.zsh" "${pkgs.oh-my-zsh}/share/oh-my-zsh/lib/spectrum.zsh"
    }
  '';
}
