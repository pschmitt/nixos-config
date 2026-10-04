{ lib, ... }:
{
  programs.zsh.initContent = lib.mkOrder 1020 ''
    if [[ -z "''${NO_COMPLETIONS:-}" ]] && (( $+commands[terraform] ))
    then
      complete -o nospace -C "$commands[terraform]" terraform
    fi

    if [[ -z "''${NO_COMPLETIONS:-}" ]] && (( $+commands[vault] ))
    then
      complete -o nospace -C "$commands[vault]" vault
    fi
  '';
}
