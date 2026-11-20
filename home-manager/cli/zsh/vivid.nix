{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (config.programs.vivid) activeTheme;
  vividColors = pkgs.runCommand "vivid-generate" { } ''
    mkdir -p $out
    ${pkgs.vivid}/bin/vivid generate ${activeTheme} > $out/ls_colors
  '';
  vividInitFile = pkgs.runCommand "vivid-zsh-init" { } ''
    printf 'export LS_COLORS=%q\\n' "$(<${vividColors}/ls_colors)" > $out
  '';
in
{
  home.packages = [ pkgs.vivid ];

  programs.vivid = {
    enable = true;
    activeTheme = "one-dark";
    # LS_COLORS comes from the build-time init file below, not a startup fork.
    enableZshIntegration = false;
  };

  xdg.configFile."zsh/custom/os/home-manager/system.zsh".text = lib.mkAfter ''
    # vivid
    source ${vividInitFile}
  '';
}
