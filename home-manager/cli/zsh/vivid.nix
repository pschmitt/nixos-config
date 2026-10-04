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
  termux.packages = lib.mkIf termuxMode [ "vivid" ];
  home.packages = lib.optionals (!termuxMode) [ pkgs.vivid ];

  programs.vivid = {
    enable = !termuxMode;
    activeTheme = "one-dark";
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
