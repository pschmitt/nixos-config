# docker-compose
if ! (( $+commands[docker-compose] ))
then
  (( $+commands[docker] )) || return
  # alias docker-compose if not available
  docker-compose() { docker compose $@ }
fi

alias dcp="docker compose"
alias ddwn="docker compose down"
alias dexec="docker compose exec"
alias dlog="docker compose logs"
alias dlogf="docker compose logs -f --tail=10"
alias dlogw="docker compose::logs"
alias drcr="docker compose::recreate"
alias drup="docker compose down; docker compose up"
alias drupd="docker compose down; docker compose up -d --remove-orphans"
alias dup="docker compose up"
alias dupd="docker compose up -d"

# vim: set ft=zsh et ts=2 sw=2 :
