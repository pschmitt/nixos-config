{ lib, ... }:
{
  environment.etc."zshenv.local".text = lib.mkAfter ''
    # Tell gpg-agent which terminal to use for curses pinentry prompts.
    # This runs before the user's zshenv, including when that file
    # disables the global zshrc to avoid alias/function collisions.
    if [[ -o interactive ]] && [[ -t 0 ]] && command -v gpg-connect-agent >/dev/null 2>&1
    then
      export GPG_TTY="$(tty)"
      gpg-connect-agent updatestartuptty /bye >/dev/null 2>&1
    fi
  '';
}
