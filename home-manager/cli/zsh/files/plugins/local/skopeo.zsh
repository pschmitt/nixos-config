(( $+commands[skopeo] )) || return

zsh::autoload-dir skopeo

alias oci::list-tags='container::list-tags'
alias docker::list-tags='container::list-tags'
