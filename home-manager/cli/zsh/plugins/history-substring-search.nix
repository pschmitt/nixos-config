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
  # After zsh-syntax-highlighting (1550), as its README asks: it highlights
  # the matched part of the command line through that plugin.
  programs.zsh.initContent = lib.mkOrder 1560 ''
    if zsh::prompt-plugins-enabled && not_in_vt
    then
      zsh::source-plugin ${
        pluginPath "history-substring-search" "zsh-history-substring-search.zsh"
          "${pkgs.zsh-history-substring-search}/share/zsh-history-substring-search/zsh-history-substring-search.zsh"
      }
      export HISTORY_SUBSTRING_SEARCH_FUZZY=1
    fi

    if (( $+widgets[history-substring-search-up] && $+widgets[history-substring-search-down] ))
    then
      [[ -n $terminfo[kcuu1] ]] && bindkey -- "$terminfo[kcuu1]" history-substring-search-up
      [[ -n $terminfo[kcud1] ]] && bindkey -- "$terminfo[kcud1]" history-substring-search-down
      bindkey -- '^[[A' history-substring-search-up
      bindkey -- '^[[B' history-substring-search-down
    fi
  '';
}
