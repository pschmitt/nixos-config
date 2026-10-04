{ lib, ... }:
{
  programs.zsh.initContent = lib.mkOrder 1410 ''
    if [[ -o interactive ]] && ! is_nixos && (( $+functions[ssh-add-common] ))
    then
      zmodload zsh/sched
      sched +1 'ssh-add-common 2>/dev/null'
    fi
  '';
}
