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
  programs.zsh.initContent = lib.mkOrder 940 ''
    if zsh::prompt-plugins-enabled && not_in_vt
    then
      zsh::source-plugin ${
        pluginPath "autosuggestions" "zsh-autosuggestions.zsh"
          "${pkgs.zsh-autosuggestions}/share/zsh-autosuggestions/zsh-autosuggestions.zsh"
      }
      export ZSH_AUTOSUGGEST_MANUAL_REBIND=1 ZSH_AUTOSUGGEST_BUFFER_MAX_SIZE=20
      ZSH_AUTOSUGGEST_STRATEGY=(match_prev_cmd history completion)
      _zsh_autosuggest_start
    fi
  '';
}
