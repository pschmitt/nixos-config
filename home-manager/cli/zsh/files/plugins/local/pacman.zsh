# pacman
if (( ! $+commands[pacman] ))
then
  return
fi

zsh::autoload-dir pacman

alias pacman::list-packages="sudo pacman -Qe | awk '{print \$1}'"

# vim: set ft=zsh et ts=2 sw=2 :
