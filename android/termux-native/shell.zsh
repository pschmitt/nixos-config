source "${${(%):-%N}:A:h}/.zshenv"
[[ -o interactive ]] || return 0

mkdir -p "$XDG_DATA_HOME/zsh" "$XDG_CACHE_HOME/termux-native/${TERMUX_GENERATION:t}"
HISTFILE="$XDG_DATA_HOME/zsh/zhistory"
HISTSIZE=10000
SAVEHIST=$HISTSIZE
setopt extended_history hist_ignore_dups hist_find_no_dups hist_reduce_blanks
setopt hist_save_no_dups hist_verify share_history append_history hist_ignore_space
setopt rc_quotes auto_pushd pushd_minus autocd extended_glob interactive_comments
setopt noclobber auto_param_slash auto_remove_slash
autoload -Uz colors && colors
autoload -Uz add-zsh-hook edit-command-line url-quote-magic bracketed-paste-magic
zle -N edit-command-line
zle -N self-insert url-quote-magic
zle -N bracketed-paste bracketed-paste-magic

typeset -g _native_plugins="$TERMUX_GENERATION/shell/plugins"
fpath=("$_native_plugins/completions/src" "$_native_plugins/oh-my-zsh/plugins/extract" $fpath)
autoload -Uz compinit
compinit -i -d "$XDG_CACHE_HOME/termux-native/${TERMUX_GENERATION:t}/zcompdump-$ZSH_VERSION"
autoload -Uz bashcompinit && bashcompinit
zmodload zsh/complist
WORDCHARS=''
setopt always_to_end auto_menu complete_in_word correct
zstyle ':completion:*' completer _complete _expand _prefix _ignored _correct _approximate
zstyle ':completion:*' use-cache on
zstyle ':completion:*' cache-path "$XDG_CACHE_HOME/termux-native/${TERMUX_GENERATION:t}"
zstyle ':completion:*' menu select=2
zstyle ':completion:*' matcher-list '' 'm:{[:lower:][:upper:]}={[:upper:][:lower:]}' '+l:|=* r:|=*'
zstyle ':completion:*' special-dirs true
zstyle ':completion:*' rehash true
zstyle ':completion:*:descriptions' format '%B%d%b'

source "$TERMUX_GENERATION/shell/keybindings.zsh"
source "$_native_plugins/oh-my-zsh/lib/spectrum.zsh"
source "$_native_plugins/oh-my-zsh/plugins/colored-man-pages/colored-man-pages.plugin.zsh"
source "$_native_plugins/oh-my-zsh/plugins/cp/cp.plugin.zsh"
source "$_native_plugins/oh-my-zsh/plugins/extract/extract.plugin.zsh"
source "$_native_plugins/oh-my-zsh/plugins/sudo/sudo.plugin.zsh"
alias x=extract
alias y='apt search' ync='pkg install -y' yqq='apt-cache policy'
alias yrm='pkg remove -y' yup='pkg upgrade' yupnc='pkg upgrade -y'
alias -g DN='&> /dev/null' L='| less' J='| jq'

source "$_native_plugins/manydots/manydots-magic"
manydots-magic
source "$_native_plugins/history-substring-search/zsh-history-substring-search.zsh"
typeset -g HISTORY_SUBSTRING_SEARCH_FUZZY=1
bindkey '^[[A' history-substring-search-up
bindkey '^[[B' history-substring-search-down
source "$_native_plugins/autopair/autopair.zsh"
bindkey '^H' backward-kill-word
source "$_native_plugins/vi-motions/motions.zsh"
source "$_native_plugins/vi-quote/vi-quote.zsh"

# These are the shared Home Manager Zsh integrations. In Termux mode they call
# the package-manager-provided commands instead of baking Linux store paths in.
source "$ZDOTDIR/custom/os/home-manager/system.zsh"

# Refuse first-run daemon acquisition: our Android executable is in the bundle.
typeset -g GITSTATUS_DAEMON="$TERMUX_GENERATION/bin/gitstatusd"
typeset -g GITSTATUS_AUTO_INSTALL=0
typeset -g POWERLEVEL9K_DISABLE_CONFIGURATION_WIZARD=true
source "$_native_plugins/powerlevel10k/gitstatus/gitstatus.plugin.zsh"
source "$TERMUX_GENERATION/shell/prompt.zsh"
source "$_native_plugins/powerlevel10k/powerlevel10k.zsh-theme"

source "$_native_plugins/autosuggestions/zsh-autosuggestions.zsh"
typeset -g ZSH_AUTOSUGGEST_MANUAL_REBIND=1 ZSH_AUTOSUGGEST_BUFFER_MAX_SIZE=20
typeset -ga ZSH_AUTOSUGGEST_STRATEGY=(match_prev_cmd history completion)
_zsh_autosuggest_start
source "$TERMUX_GENERATION/shell/plugins/example.zsh"

# Host extensions are runtime inputs, not embedded in a public artifact.
if [[ -r "$XDG_CONFIG_HOME/termux-native/host.zsh" ]]
then
  source "$XDG_CONFIG_HOME/termux-native/host.zsh"
fi
# Highlighting must observe all the widgets registered above.
source "$_native_plugins/syntax-highlighting/zsh-syntax-highlighting.zsh"
ZSH_HIGHLIGHT_STYLES[comment]='fg=006'
unset _native_plugins

# Zinit integrations may rewrite PATH while loading plugins. Restore the
# selected generation and Termux package directories after those changes so
# bundled commands such as nixpp stay available in the interactive shell.
path=("$TERMUX_GENERATION/bin" "$PREFIX/bin" $path)

typeset -g TERMUX_NATIVE_READY=1
true

# vim: set ft=zsh et ts=2 sw=2 :
