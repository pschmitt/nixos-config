{ lib, ... }:
{
  programs.zsh.initContent = lib.mkOrder 600 ''
    if ! is_nixos && [[ -r /etc/profile.d/nix.sh ]] && (( $+commands[nix] ))
    then
      ${builtins.readFile ../hm.zsh}
    fi
  '';
}
