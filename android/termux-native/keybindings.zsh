# Ported from the existing zsh-config bindings; no zinit dependency.
bindkey -v
zmodload zsh/terminfo
terminfo_bind() {
  [[ -n "${terminfo[$1]}" ]] && bindkey "${terminfo[$1]}" "$2"
  return 0
}
terminfo_bind khome beginning-of-line
terminfo_bind kend end-of-line
terminfo_bind kich1 overwrite-mode
terminfo_bind kdch1 delete-char
terminfo_bind kcuu1 up-line-or-history
terminfo_bind kcud1 down-line-or-history
terminfo_bind kcub1 backward-char
terminfo_bind kcuf1 forward-char
terminfo_bind kpp beginning-of-buffer-or-history
terminfo_bind knp end-of-buffer-or-history
terminfo_bind kcbt reverse-menu-complete
bindkey '^[[1~' beginning-of-line
bindkey '^[[4~' end-of-line
bindkey '^[[1;5C' forward-word
bindkey '^[[1;5D' backward-word
bindkey '^[[3;5~' kill-word
bindkey '^[z' undo
bindkey '^[y' redo
bindkey '^i' expand-or-complete-prefix
bindkey '^[m' copy-prev-shell-word
bindkey '^E' edit-command-line
bindkey '^[e' edit-command-line
bindkey '^[#' pound-insert
zle_remove_newlines() {
  BUFFER="${BUFFER//$'\n'/ }"
  CURSOR=$#BUFFER
}
zle -N zle_remove_newlines
bindkey '^X' zle_remove_newlines

# vim: set ft=zsh et ts=2 sw=2 :
