{ lib, ... }:
{
  environment.etc.zshenv.text = lib.mkAfter ''
    export ZDOTDIR="''${ZDOTDIR:-$HOME/.config/zsh}"
  '';
}
