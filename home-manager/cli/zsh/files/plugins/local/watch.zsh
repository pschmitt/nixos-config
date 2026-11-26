(( $+commands[hwatch] )) || return

zsh::autoload-dir watch

# Aliases
alias zw="zwatch"
alias watch="watch --color"

if (( ! $+commands[watch] ))
then
  alias watch=zwatch
fi
