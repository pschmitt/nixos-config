(( $+commands[hwatch] )) || return

# Aliases
alias zw="zwatch"
alias watch="watch --color"

if (( ! $+commands[watch] ))
then
  alias watch=zwatch
fi
