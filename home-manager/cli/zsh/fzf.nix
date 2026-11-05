{
  config,
  lib,
  pkgs,
  ...
}:
let
  termuxMode = config.termux.enable or false;
  fzfInitFile = pkgs.runCommand "fzf-init" { } ''
    mkdir -p $out
    ${pkgs.fzf}/bin/fzf --zsh > $out/init.zsh
  '';
in
{
  # fzf-preview: the --preview helper the zsh fzf plugin and functions use.
  home.packages = lib.optionals (!termuxMode) [
    pkgs.fzf
    pkgs.fzf-preview
  ];

  termux.packages = lib.mkIf termuxMode [ "fzf" ];

  xdg.configFile."zsh/custom/os/home-manager/system.zsh".text = lib.mkAfter (
    (
      if termuxMode then
        ''
          # fzf
          source "$TERMUX_GENERATION/home/.config/zsh/termux/fzf-init.zsh"
        ''
      else
        ''
          # fzf
          source ${fzfInitFile}/init.zsh
        ''
    )
    + ''
      # Input at the bottom, preview above the list on narrow (portrait) terminals.
      export FZF_DEFAULT_OPTS='
        --ansi
        --multi
        --history "'"''${XDG_DATA_HOME:-$HOME/.local/share}"'/fzf_history"
        --height 100%
        --info=inline
        --layout default
        --preview-window "right,66%,border-none,<80(up,80%,border-none)"
        --preview "fzf-preview {}"
        --color "preview-bg:#223344"
        --bind "alt-a:select-all,alt-d:deselect-all,ctrl-/:toggle-preview"
        --bind "alt-k:change-preview-window(up|right)"
      '
    ''
  );

  xdg.configFile."zsh/termux/fzf-init.zsh" = lib.mkIf termuxMode {
    source = "${fzfInitFile}/init.zsh";
  };
}
