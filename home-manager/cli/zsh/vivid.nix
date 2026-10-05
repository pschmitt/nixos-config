{
  config,
  lib,
  pkgs,
  ...
}:
let
  termuxMode = config.termux.enable or false;
  vividColors = pkgs.runCommand "vivid-generate" { } ''
    mkdir -p $out
    ${pkgs.vivid}/bin/vivid generate ${config.programs.vivid.activeTheme} > $out/ls_colors
  '';
in
{
  home.packages = lib.optionals (!termuxMode) [ pkgs.vivid ];

  programs.vivid = {
    enable = true;
    activeTheme = "one-dark";
    package = lib.mkIf termuxMode null;
  };

  xdg.configFile."zsh/custom/os/home-manager/system.zsh".text = lib.mkAfter (
    if termuxMode then
      ''
        # vivid
        export LS_COLORS="$(vivid generate ${config.programs.vivid.activeTheme})"
        zstyle ':completion:*:default' list-colors "''${(s.:.)LS_COLORS}"
      ''
    else
      ''
        # vivid
        export LS_COLORS="$(cat ${vividColors}/ls_colors)"
      ''
  );
}
