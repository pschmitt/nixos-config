[[ -o interactive ]] || return 0

typeset -g _native_yadm_config=${TERMUX_NATIVE_YADM_CONFIG:-0}
mkdir -p "$XDG_CACHE_HOME/termux-native/${TERMUX_GENERATION:t}"
if [[ "$_native_yadm_config" != 1 ]]
then
  mkdir -p "$XDG_DATA_HOME/zsh"
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
fi

typeset -g _native_plugins="$TERMUX_GENERATION/shell/plugins"
typeset -gA CUSTOM_COMPS
typeset -ga COMPS_TO_SOURCE
fpath=("$_native_plugins/completions/src" "$_native_plugins/oh-my-zsh/plugins/extract" $fpath)
autoload -Uz compinit
compinit -i -d "$XDG_CACHE_HOME/termux-native/${TERMUX_GENERATION:t}/zcompdump-$ZSH_VERSION"
if [[ "$_native_yadm_config" != 1 ]]
then
  autoload -Uz bashcompinit && bashcompinit
  zmodload zsh/complist
fi
if [[ -r "$TERMUX_GENERATION/home/.config/zsh/completions/source-me.zsh" ]]
then
  source "$TERMUX_GENERATION/home/.config/zsh/completions/source-me.zsh"
fi
if [[ "$_native_yadm_config" != 1 ]]
then
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
fi

if [[ "$_native_yadm_config" != 1 ]]
then
  source "$TERMUX_GENERATION/shell/keybindings.zsh"
fi
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
source "$TERMUX_GENERATION/home/.config/zsh/custom/os/home-manager/system.zsh"

# Refuse first-run daemon acquisition: our Android executable is in the bundle.
typeset -g GITSTATUS_DAEMON="$TERMUX_GENERATION/bin/gitstatusd"
typeset -g GITSTATUS_AUTO_INSTALL=0
typeset -g POWERLEVEL9K_DISABLE_CONFIGURATION_WIZARD=true
source "$_native_plugins/powerlevel10k/gitstatus/gitstatus.plugin.zsh"
source "$_native_plugins/powerlevel10k/powerlevel10k.zsh-theme"
if [[ "${TERMUX_NATIVE_YADM_CONFIG:-}" == 1 && -r "$ZDOTDIR/p10k.zsh" ]]
then
  source "$ZDOTDIR/p10k.zsh"
else
  source "$TERMUX_GENERATION/shell/prompt.zsh"
fi

source "$_native_plugins/autosuggestions/zsh-autosuggestions.zsh"
typeset -g ZSH_AUTOSUGGEST_MANUAL_REBIND=1 ZSH_AUTOSUGGEST_BUFFER_MAX_SIZE=20
typeset -ga ZSH_AUTOSUGGEST_STRATEGY=(match_prev_cmd history completion)
_zsh_autosuggest_start
source "$TERMUX_GENERATION/shell/plugins/example.zsh"

# Zinit's regular local-plugin block sources these private files at runtime.
# Keep them on-device and load them directly for Termux instead of bundling
# private dotfiles or starting Zinit.
if [[ "$_native_yadm_config" == 1 ]]
then
  () {
    setopt localoptions nullglob
    multisrc \
      "$ZDOTDIR"/plugins/local/*.zsh \
      "$ZDOTDIR"/plugins/local/work/*.zsh \
      "$ZDOTDIR"/plugins/local/99-after/*.zsh
  }
  if [[ -r "$ZDOTDIR/zinit/completions.zsh" ]]
  then
    () {
      zzinit() { : }
      source "$ZDOTDIR/zinit/completions.zsh"
      unfunction zzinit

      local completion_pattern completion_file
      for completion_pattern in "${COMPS_TO_SOURCE[@]}"
      do
        for completion_file in ${(e)~completion_pattern}
        do
          [[ -r "$completion_file" ]] && source "$completion_file"
        done
      done
      __init_custom_completions
    }
  fi
  if [[ "${TERMUX_RUN_MODE:-}" != ci && -r "$ZDOTDIR/secrets.zsh" ]]
  then
    source "$ZDOTDIR/secrets.zsh"
  fi
  typeset -g TERMUX_NATIVE_USER_PLUGINS_READY=1
fi

# Host extensions are runtime inputs, not embedded in a public artifact.
if [[ -r "$XDG_CONFIG_HOME/termux-native/host.zsh" ]]
then
  source "$XDG_CONFIG_HOME/termux-native/host.zsh"
fi
# Highlighting must observe all the widgets registered above.
source "$_native_plugins/syntax-highlighting/zsh-syntax-highlighting.zsh"
ZSH_HIGHLIGHT_STYLES[comment]='fg=006'
unset _native_plugins
unset _native_yadm_config

# Keep generated commands and Termux APT commands available after shell
# integrations adjust PATH.
path=("$TERMUX_GENERATION/bin" "$PREFIX/bin" $path)

typeset -g TERMUX_NATIVE_READY=1
true

# vim: set ft=zsh et ts=2 sw=2 :
