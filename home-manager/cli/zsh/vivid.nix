{
  config,
  lib,
  pkgs,
  ...
}:
{
  home.packages = with pkgs; [
    vivid
  ];

  programs.vivid = {
    enable = true;
    activeTheme = "one-dark";
  };

  xdg.configFile."zsh/custom/os/nixos/system.zsh".text = lib.mkAfter ''
    # vivid
    export LS_COLORS="$(cat ${
      (pkgs.runCommand "vivid-generate" { } ''
        mkdir -p $out
        ${pkgs.vivid}/bin/vivid generate ${config.programs.vivid.activeTheme} > $out/ls_colors
      '')
    }/ls_colors)"
  '';
}
