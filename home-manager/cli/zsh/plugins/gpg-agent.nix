{ lib, ... }:
{
  # ssh-add-common comes from the (deferred) local plugins.
  programs.zsh.initContent = lib.mkOrder 1390 ''
    zsh::gpg-agent-ssh-add() {
      [[ -o interactive ]] && ! is_nixos && (( $+functions[ssh-add-common] )) || return 0
      zmodload zsh/sched
      sched +1 'ssh-add-common 2>/dev/null'
    }
    zsh_after_local_plugins+=(zsh::gpg-agent-ssh-add)
  '';
}
