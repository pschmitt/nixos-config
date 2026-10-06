{
  config,
  lib,
  pkgs,
  ...
}:
let
  termuxMode = config.termux.enable or false;
  activeTheme = if termuxMode then "catppuccin-mocha" else config.programs.vivid.activeTheme;
  vividColors = pkgs.runCommand "vivid-generate" { } ''
    mkdir -p $out
    ${pkgs.vivid}/bin/vivid generate ${activeTheme} > $out/ls_colors
  '';
  vividInitFile = pkgs.runCommand "vivid-zsh-init" { } ''
    printf 'export LS_COLORS=%q\\n' "$(<${vividColors}/ls_colors)" > $out
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
        source "$TERMUX_GENERATION/home/.config/zsh/termux/vivid.zsh"
        zstyle ':completion:*:default' list-colors "''${(s.:.)LS_COLORS}"
      ''
    else
      ''
        # vivid
        export LS_COLORS="$(cat ${vividColors}/ls_colors)"
      ''
  );

  xdg.configFile."zsh/termux/vivid.zsh" = lib.mkIf termuxMode { source = vividInitFile; };
}
