{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (import ./path.nix { inherit config lib; }) pluginTree;
  completions =
    pluginTree "oh-my-zsh" "plugins/docker/completions"
      "${pkgs.oh-my-zsh}/share/oh-my-zsh/plugins/docker/completions";
in
{
  # Only the docker completion from oh-my-zsh's docker plugin, like the yadm
  # shell (OMZP::docker/completions/_docker): sourcing the plugin itself adds
  # ~45 aliases (dps, dr, ...). Before compinit (completions.nix, 1000).
  programs.zsh.initContent = lib.mkOrder 990 ''
    if [[ -z "$NO_PLUGINS" ]] && (( $+commands[docker] ))
    then
      fpath=("${completions}" $fpath)
    fi
  '';
}
