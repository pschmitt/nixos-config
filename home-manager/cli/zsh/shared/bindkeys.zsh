# Key bindings shared by the Home Manager and the NixOS-level Zsh config.
zmodload zsh/terminfo

# Usage: terminfo_bind CAPABILITY WIDGET
# Bind the key the terminal's terminfo entry defines, if it defines one.
terminfo_bind() {
  [[ -n "${terminfo[$1]}" ]] && bindkey -- "${terminfo[$1]}" "$2"
}

autoload -Uz edit-command-line
zle -N edit-command-line
bindkey '^e' edit-command-line
bindkey '^[z' undo
bindkey '^[y' redo
bindkey '^[m' copy-prev-shell-word
