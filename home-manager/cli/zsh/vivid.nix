{
  config,
  lib,
  pkgs,
  ...
}:
let
  termuxMode = config.termux.enable or false;
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
      ''
    else
      ''
        # vivid
        export LS_COLORS="$(cat ${
          (pkgs.runCommand "vivid-generate" { } ''
            mkdir -p $out
            ${pkgs.vivid}/bin/vivid generate ${config.programs.vivid.activeTheme} > $out/ls_colors
          '')
        }/ls_colors)"
      ''
  );
}
