# FZF
if (( ! $+commands[fzf] ))
then
  return
fi

export FZF_DEFAULT_COMMAND='fd --type f --hidden -E "**/.git/" --color=always'
export FZF_DEFAULT_OPTS='
  --ansi
  --multi
  --history "'${XDG_DATA_HOME}'/fzf_history"
  --height 100%
  --info=inline
  --layout default
  --preview-window "right,66%,border-none,<80(up,80%,border-none)"
  --preview "fzf-preview {}"
  --color "preview-bg:#223344"
  --bind "alt-a:select-all,alt-d:deselect-all,ctrl-/:toggle-preview"
  --bind "alt-k:change-preview-window(up|right)"
  --bind "alt-0:transform:fzf-preview --next-mode"
'
export FZF_ALT_C_COMMAND="fd -H -E \"**/.git/\" -t d --color=always"
export FZF_ALT_C_OPTS="--header \"Change directory\" --preview \"tree -C -- {}\""
export FZF_CTRL_T_COMMAND="fd -H -E \"**/.git/\" -t f --color=always"
export FZF_CTRL_T_OPTS="--preview=\"bat --style=numbers --color=always -- {}\""
# FIXME The ctrl-y shortcut doesn't work
export FZF_CTRL_R_OPTS="
  --preview 'echo {}' --preview-window up:3:hidden:wrap
  --bind 'ctrl-/:toggle-preview'
  --bind 'ctrl-y:execute-silent(echo -n {2..} | wl-copy)+abort'
  --color header:italic
  --header 'Press CTRL-Y to copy command into clipboard'"

alias cdf="fzf::cd"
alias rgv="fzf::rg-files"
alias vimrg="fzf::rg-files"

zsh::autoload-dir fzf

# https://junegunn.github.io/fzf/tips/ripgrep-integration/
vim::rg() (
  local cmd_reload='
    rg --column --color=always --smart-case {q} |
    # only show filenames:line:column, we already have a previe window
    awk -F'':'' ''{ print $1 ":" $2 ":" $3 }'' || :
  '
  local cmd_open='
    if [[ $FZF_SELECT_COUNT -eq 0 ]]
    then
      # No selection. Open the current line in $EDITOR.
      $EDITOR {1} +{2}
    else
      # Build quickfix list for the selected items.
      $EDITOR +cw -q {+f}
    fi
  '

  fzf --disabled --ansi --multi \
    --bind "start:reload:$cmd_reload" \
    --bind "change:reload:$cmd_reload" \
    --bind "enter:become:$cmd_open" \
    --bind "ctrl-o:execute:$cmd_open" \
    --delimiter : \
    --preview 'fzf-preview {1}:{2}' \
    --query "$*"
)

# vim: set ft=zsh et ts=2 sw=2 :
