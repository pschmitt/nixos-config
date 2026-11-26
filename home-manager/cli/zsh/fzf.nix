{ lib, pkgs, ... }:
let
  fzfInitFile = pkgs.runCommand "fzf-init" { } ''
    mkdir -p $out
    ${pkgs.fzf}/bin/fzf --zsh > $out/init.zsh
  '';
in
{
  # fzf-preview: the --preview helper the zsh fzf plugin and functions use.
  home.packages = [
    pkgs.fzf
    pkgs.fzf-preview
  ];

  # The options are exported before the bindings load: fzf's zsh widgets
  # read FZF_CTRL_T_COMMAND & co. (an empty one disables its binding).
  programs.zsh.initContent = lib.mkOrder 700 ''
    if [[ -o interactive ]]
    then
      export FZF_DEFAULT_COMMAND='fd --type f --hidden -E "**/.git/" --color=always'
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
        --bind "alt-0:transform:fzf-preview --next-mode"
      '
      export FZF_ALT_C_COMMAND='fd -H -E "**/.git/" -t d --color=always'
      export FZF_ALT_C_OPTS='--header "Change directory" --preview "tree -C -- {}"'
      export FZF_CTRL_T_COMMAND='fd -H -E "**/.git/" -t f --color=always'
      export FZF_CTRL_T_OPTS='--preview "bat --style=numbers --color=always -- {}"'
      # FIXME The ctrl-y shortcut doesn't work
      export FZF_CTRL_R_OPTS="
        --preview 'echo {}' --preview-window up:3:hidden:wrap
        --bind 'ctrl-/:toggle-preview'
        --bind 'ctrl-y:execute-silent(echo -n {2..} | wl-copy)+abort'
        --color header:italic
        --header 'Press CTRL-Y to copy command into clipboard'"

      source ${fzfInitFile}/init.zsh
    fi
  '';
}
