zsh::autoload-dir sed

alias sed-and-replace-recursive="sed::replace-recursive"

if (( ! $+commands[tac] ))
then
  tac() { sed -n '1! G; $ p; h' $@ }
fi

# vim: set ft=zsh et ts=2 sw=2 :
