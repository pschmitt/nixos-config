{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (import ./path.nix { inherit config lib; }) pluginPath;
  emojiFzfPlugin = pkgs.fetchFromGitHub {
    owner = "pschmitt";
    repo = "emoji-fzf.zsh";
    rev = "55c7cb68b16f460f01b92651c11a7190e803f236";
    hash = "sha256-/yNpAEQlR+5n8cJqcG5+VciVdguxSd7At2XadUbva6g=";
  };
in
{
  programs.zsh.initContent = lib.mkOrder 960 ''
    [[ -z "$NO_PLUGINS" ]] && zsh::source-plugin ${
      pluginPath "emoji-fzf" "emoji-fzf.plugin.zsh" "${emojiFzfPlugin}/emoji-fzf.plugin.zsh"
    }
  '';
}
