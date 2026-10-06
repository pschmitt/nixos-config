# Autoload cache for the yadm-managed local plugins (~330 files, ~1800
# functions). Sourcing them costs ~400 ms per shell, `ssh host cmd` and zhj
# included, although a command usually needs a single function.
#
# zsh::local-plugins-compile sources every plugin once (in a background
# shell) and records what each file changes:
#   - files that only define functions/aliases/completions: their functions
#     become autoload files (compiled into one digest), their aliases,
#     compdefs and CUSTOM_COMPS entries are replayed from eager.zsh;
#   - files with other effects (variables, options, hooks, widgets, keys,
#     zstyles, modules, traps, runtime checks): sourced as before.
# The digest is written with `zcompile -c` straight from the parsed,
# in-memory functions (aliases expanded as at definition time, RC_QUOTES,
# multibyte text), so autoloading them (-U) is exactly today's behaviour.
#
# Correctness never depends on the cache: every shell compares a cheap key
# (plugin file list, newest mtime, zsh version, rc identity) and falls back
# to sourcing the files directly while a rebuild runs in the background.
# Edit plugin files freely; ZSH_LOCAL_PLUGIN_CACHE=0 disables the cache.
#
# What plugins do at load time can also depend on the environment
# (`(( $+commands[foo] )) || return`, `alias x="... $EMAIL"`), so the
# compiler collects what their top-level code reads (spec) and every shell
# fingerprints it: where looked-up commands resolve, the values of the
# variables read, and only set/unset for per-session ones (SSH_CONNECTION,
# TMUX, ...). Each environment fingerprint gets its own build (index).
#
# Expects zsh_local_plugin_dirs, zsh::local-plugin-files and
# zsh::source-plugin (runtime.nix).

zmodload -F zsh/stat b:zstat 2>/dev/null

typeset -g ZSH_LOCAL_PLUGIN_CACHE_DIR="${ZSH_CACHE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/zsh}/local-plugins"

zsh::local-plugins-cache-enabled() {
  [[ "${ZSH_LOCAL_PLUGIN_CACHE:-1}" != 0 ]] && (( $+builtins[zstat] ))
}

# REPLY=key; reply=plugin files
zsh::local-plugins-cache-key() {
  zsh::local-plugin-files
  local -a newest stamp
  local dir newest_mtime=0
  for dir in $zsh_local_plugin_dirs
  do
    newest+=("$dir"(N/) "$dir"/*.zsh(N.om[1]))
  done
  for dir in $newest
  do
    zstat -A stamp +mtime -- "$dir" 2>/dev/null || continue
    (( stamp[1] > newest_mtime )) && newest_mtime=$stamp[1]
  done
  REPLY="v1|$ZSH_VERSION|${${:-$ZDOTDIR/.zshrc}:A}|$newest_mtime|${#reply}|${(j.:.)reply}"
}

# REPLY=environment fingerprint for the given spec entries:
#   c:CMD   where CMD resolves ($commands)
#   p:NAME  whether NAME is set and non-empty (per-session variables)
#   v:NAME  the value of NAME
#   P       the whole PATH (dynamic command lookups)
zsh::local-plugins-env-fp() {
  local entry
  local -a fp
  for entry in "$@"
  do
    case "$entry" in
      c:*) fp+=("$entry=${commands[${entry#c:}]}") ;;
      p:*) fp+=("$entry=${${(P)${entry#p:}}:+1}") ;;
      v:*) fp+=("$entry=${(P)${entry#v:}}") ;;
      P) fp+=("P=$PATH") ;;
    esac
  done
  REPLY="${(pj:\x1f:)fp}"
}

# Find the build for this plugin set and environment: sets __zlp_build.
zsh::local-plugins-cache-fresh() {
  zsh::local-plugins-cache-enabled || return 1
  local base="$ZSH_LOCAL_PLUGIN_CACHE_DIR"
  [[ -r "$base/index" && -r "$base/spec" ]] || return 1
  # mapfile: `read` goes byte by byte, ~4 ms for the ~20 KB key
  zmodload -F zsh/mapfile p:mapfile 2>/dev/null || return 1
  local -a reply idx
  local REPLY key fp
  integer i
  zsh::local-plugins-cache-key
  key="$REPLY"
  zsh::local-plugins-env-fp "${(@ps:\0:)mapfile[$base/spec]}"
  fp="$REPLY"
  idx=("${(@ps:\0:)mapfile[$base/index]}")
  for (( i = 1; i < ${#idx}; i += 2 ))
  do
    [[ "${idx[i+1]}" == "$fp" ]] || continue
    [[ -r "$base/${idx[i]}/head.zsh" && "${mapfile[$base/${idx[i]}/key]%$'\n'}" == "$key" ]] || return 1
    typeset -g __zlp_build="$base/${idx[i]}"
    return 0
  done
  return 1
}

# reply=the cached commands to run after head.zsh, in plugin order.
zsh::local-plugins-cache-body() {
  zmodload -F zsh/mapfile p:mapfile 2>/dev/null || return 1
  reply=("${(@ps:\0:)mapfile[$__zlp_build/body]}")
}

# Load from the cache synchronously; returns 1 (having done nothing) when it
# is stale. The interactive loader uses head.zsh + body itself (async).
zsh::local-plugins-cache-load() {
  zsh::local-plugins-cache-fresh || return 1
  local -a reply
  zsh::local-plugins-cache-body || return 1
  zsh::local-plugins-prepare
  source "$__zlp_build/head.zsh"
  typeset -g ZSH_LOCAL_PLUGINS_CACHE_BUILD="$__zlp_build"
  local cmd
  for cmd in "${reply[@]}"
  do
    eval "$cmd"
  done
}

zsh::local-plugins-compile-locked() {
  local pid
  [[ -r "$ZSH_LOCAL_PLUGIN_CACHE_DIR/lock/pid" ]] || return 1
  IFS= read -r pid < "$ZSH_LOCAL_PLUGIN_CACHE_DIR/lock/pid" && kill -0 "$pid" 2>/dev/null
}

zsh::local-plugins-compile-async() {
  zsh::local-plugins-cache-enabled || return 0
  zsh::local-plugins-compile-locked && return 0
  # Ignore SIGHUP: the shell that triggered this may be an ssh session.
  zsh::local-plugins-compile-command &>/dev/null </dev/null &!
}

# Compile in an interactive (-i) shell, so top-level `[[ -o interactive ]]`
# code in plugins behaves as in a real shell; prompt plugins, completions,
# instant prompt and the local plugins themselves are skipped while .zshrc
# loads.
zsh::local-plugins-compile-command() {
  ZHJ=1 NO_LOCAL_PLUGINS=1 NO_PLUGINS=1 NO_COMPLETIONS=1 NO_INSTANT_PROMPT=1 \
    zsh -f -i -c 'trap "" HUP; source "$ZDOTDIR/.zshenv"; source "$ZDOTDIR/.zshrc"; zsh::local-plugins-compile'
}

# Reports what this shell loaded: the environment fingerprint is only
# meaningful before the plugins ran (they change the environment).
zsh::local-plugins-cache-status() {
  local -a idx
  [[ -r "$ZSH_LOCAL_PLUGIN_CACHE_DIR/index" ]] && idx=("${(@ps:\0:)$(<"$ZSH_LOCAL_PLUGIN_CACHE_DIR/index")}")
  if ! zsh::local-plugins-cache-enabled
  then
    print -r -- "local plugin cache: disabled"
  elif [[ -n "${ZSH_LOCAL_PLUGINS_CACHE_BUILD:-}" ]]
  then
    print -r -- "local plugin cache: this shell loaded ${ZSH_LOCAL_PLUGINS_CACHE_BUILD:t} ($(<"$ZSH_LOCAL_PLUGINS_CACHE_BUILD/summary"); $(( ${#idx} / 2 )) environment variant(s))"
  elif zsh::local-plugins-compile-locked
  then
    print -r -- "local plugin cache: rebuilding"
  else
    print -r -- "local plugin cache: not used by this shell (stale or no build for its environment yet; $(( ${#idx} / 2 )) variant(s))"
  fi
}

zsh::local-plugins-compile() {
  zsh::local-plugins-cache-enabled || return 1
  local base="$ZSH_LOCAL_PLUGIN_CACHE_DIR"
  mkdir -p -- "$base" && chmod 700 -- "$base" || return 1

  # The lock holds the compiler's pid; a lock whose process is gone is stale.
  if [[ -d "$base/lock" ]] && ! zsh::local-plugins-compile-locked
  then
    rm -rf -- "$base/lock"
  fi
  mkdir -- "$base/lock" 2>/dev/null || return 0
  print -r -- "$$" >| "$base/lock/pid"
  {
    # Builds without a key never completed (we hold the lock).
    local build
    for build in "$base"/build.*(N/)
    do
      [[ -e "$build/key" ]] || rm -rf -- "$build"
    done
    # Subshell: keep the caller's umask, options and functions untouched.
    # Replayed parameter values end up in eager.zsh, hence umask 077.
    ( umask 077; zsh::local-plugins-compile-into "$base" )
  } always {
    rm -rf -- "$base/lock"
  }
}

zsh::local-plugins-compile-into() {
  local base="$1"
  zmodload zsh/datetime zsh/parameter

  # mtimes have 1 s resolution: don't snapshot a file edited this second.
  local -a reply
  local REPLY
  zsh::local-plugins-cache-key
  local key="$REPLY"
  local -a files=("${reply[@]}")
  local -a key_parts=("${(@s:|:)key}")
  (( key_parts[4] >= EPOCHSECONDS )) && sleep 1

  local build="$base/build.$$.$EPOCHSECONDS"
  mkdir -p -- "$build" || return 1

  # Source the plugins like an interactive shell does: interactive options,
  # none of the zhj/eval-mode markers set.
  (( $+functions[zsh::interactive-options] )) && zsh::interactive-options
  unset ZHJ NO_PLUGINS NO_COMPLETIONS NO_LOCAL_PLUGINS NO_INSTANT_PROMPT

  # Stubs: record top-level side effects instead of performing them where
  # they can't work outside a terminal (compdef, zle, bindkey).
  typeset -g __zlp_effect=0
  typeset -ga __zlp_compdefs
  compdef() { __zlp_compdefs+=("compdef ${(j: :)${(@q)@}}") }
  zle() { [[ "$1" == -(l|L|a|la|lL) || $# == 0 ]] || __zlp_effect="zle $1"; return 0 }
  bindkey() { [[ $# == 0 || "$1" == -(l|L|M) ]] || __zlp_effect=bindkey; builtin bindkey "$@" 2>/dev/null }
  zstyle() { [[ "$1" == -(L|g|s|t|T|b|a|m) ]] || __zlp_effect=zstyle; builtin zstyle "$@" }
  zmodload() { __zlp_effect="zmodload $*"; builtin zmodload "$@" }
  trap() { __zlp_effect=trap; builtin trap "$@" }
  sched() { __zlp_effect=sched }

  # Parameters that change by themselves or belong to this function.
  local volatile='(RANDOM|SECONDS|EPOCHREALTIME|EPOCHSECONDS|LINENO|_|status|pipestatus|TTYIDLE|ZSH_SUBSHELL|ZSH_EVAL_CONTEXT|zsh_eval_context|funcstack|funcfiletrace|funcsourcetrace|functrace|reply|REPLY|match|mbegin|mend|MATCH|MBEGIN|MEND|OPTIND|OPTARG|__zlp_*|CUSTOM_COMPS|CUSTOM_COMPS_STATIC)'
  local -a tracked_specials=(path PATH fpath FPATH manpath MANPATH cdpath CDPATH)

  zsh::_zlp-param-snapshot() {
    # name -> type + value, for globals (and a few path-like specials)
    local p t
    reply=()
    for p t in "${(@kv)parameters}"
    do
      [[ "$p" == ${~volatile} || "$t" == *local* ]] && continue
      [[ "$t" == *special* && ${tracked_specials[(Ie)$p]} == 0 ]] && continue
      case "$t" in
        association*) reply+=("$p" "$t:${(j:\0:)${(@Pkv)p}}") ;;
        array*) reply+=("$p" "$t:${(Pj:\0:)p}") ;;
        *) reply+=("$p" "$t:${(P)p}") ;;
      esac
    done
  }

  # Pass 1: source every file in order and record what it changed.
  # Function changes are detected via functions_source (the defining file),
  # which avoids copying all function bodies per file; definitions that
  # don't come from the file itself (eval, generators) make it eager.
  local -A owner fsrc0 a0 g0 s0 o0 cc0 ccs0 file_effect file_replay file_funcs file_reason
  local -a p0 pnow
  local file n v
  integer eager_count=0

  # What the plugins' top-level (load-time) code reads, from their source:
  # each file is parsed as a function body and printed back by zsh, nested
  # function definitions are dropped. Done for every file (not only the
  # replayed ones) so the spec doesn't depend on the environment.
  local -a spec
  zsh::_zlp-spec "${files[@]}"
  spec=("${reply[@]}")
  # Fingerprint the environment before plugins change it.
  zsh::local-plugins-env-fp "${spec[@]}"
  local fp="$REPLY"

  # A plugin re-exporting an inherited variable with the same value would
  # go unnoticed (and fresh shells without it would miss the export), so
  # inherited exports lose their export flag while each file is sourced.
  # Values stay; essentials stay exported for child processes.
  local -a inherited_exports
  local t
  for n t in "${(@kv)parameters}"
  do
    [[ "$t" == *export* && "$t" != *special* ]] || continue
    [[ "$n" == (HOME|USER|LOGNAME|SHELL|TERM|LANG|LC_*|TMPDIR|ZDOTDIR|XDG_*|NIX_PATH|NIX_PROFILES|NIX_SSL_CERT_FILE|NIX_USER_PROFILE_DIR|NIX_REMOTE|LOCALE_ARCHIVE*|SSL_CERT_FILE|TZDIR|TERMUX_*|PREFIX|LD_PRELOAD|ANDROID_*) ]] && continue
    inherited_exports+=("$n")
  done

  zsh::local-plugins-prepare
  for file in "${files[@]}"
  do
    (( ${#inherited_exports} )) && typeset -g +x -- "${inherited_exports[@]}"
    fsrc0=("${(@kv)functions_source}")
    a0=("${(@kv)aliases}") g0=("${(@kv)galiases}") s0=("${(@kv)saliases}")
    zsh::_zlp-param-snapshot; p0=("${(@)reply}")
    o0=("${(@kv)options}")
    cc0=("${(@kv)CUSTOM_COMPS}") ccs0=("${(@kv)CUSTOM_COMPS_STATIC}")
    __zlp_effect=0 __zlp_compdefs=()

    zsh::source-plugin "$file" &>/dev/null

    local -a defined=() replay=()
    local effect=$__zlp_effect

    for n v in "${(@kv)functions_source}"
    do
      [[ "$v" == "${fsrc0[$n]-__zlp_unset__}" ]] && continue
      [[ "$n" == (compdef|zle|bindkey|zstyle|zmodload|trap|sched|zsh::_zlp-*) ]] && continue
      defined+=("$n")
      [[ "$v" == "$file" ]] || effect="dynamic $n"
      # Functions that look up where they were defined would see the cache
      # instead of the plugin file (top-level code is unaffected).
      [[ "${functions[$n]}" == *(%x|functions_source|funcsourcetrace)* ]] && effect="location $n"
      # traps, autoload stubs and unrepresentable names stay eager
      [[ "$n" == TRAP* || "$n" == */* || "$n" == .* ]] && effect="name $n"
    done
    for n in "${(@k)fsrc0}"
    do
      (( $+functions[$n] )) || effect="unfunction $n"
    done

    for n v in "${(@kv)aliases}"
    do
      [[ "$v" == "${a0[$n]-__zlp_unset__}" ]] || replay+=("alias -- ${(q)n}=${(q)v}")
    done
    for n v in "${(@kv)galiases}"
    do
      [[ "$v" == "${g0[$n]-__zlp_unset__}" ]] || replay+=("alias -g -- ${(q)n}=${(q)v}")
    done
    for n v in "${(@kv)saliases}"
    do
      [[ "$v" == "${s0[$n]-__zlp_unset__}" ]] || replay+=("alias -s -- ${(q)n}=${(q)v}")
    done
    (( ${#aliases} < ${#a0} || ${#galiases} < ${#g0} || ${#saliases} < ${#s0} )) && effect=unalias
    for n v in "${(@kv)CUSTOM_COMPS}"
    do
      [[ "$v" == "${cc0[$n]-__zlp_unset__}" ]] || replay+=("CUSTOM_COMPS[${(q)n}]=${(q)v}")
    done
    for n v in "${(@kv)CUSTOM_COMPS_STATIC}"
    do
      [[ "$v" == "${ccs0[$n]-__zlp_unset__}" ]] || replay+=("CUSTOM_COMPS_STATIC[${(q)n}]=${(q)v}")
    done
    (( ${#CUSTOM_COMPS} < ${#cc0} || ${#CUSTOM_COMPS_STATIC} < ${#ccs0} )) && effect=custom-comps-removed
    for n in "${__zlp_compdefs[@]}"
    do
      replay+=("(( \$+functions[compdef] )) && $n")
    done

    for n in "${inherited_exports[@]}"
    do
      [[ "${parameters[$n]}" == *export* ]] && { effect="export $n"; break }
    done
    if [[ "$effect" == 0 ]]
    then
      zsh::_zlp-param-snapshot; pnow=("${(@)reply}")
      if [[ "${(j:\0:)pnow}" != "${(j:\0:)p0}" ]]
      then
        # New plain globals are data (like aliases) and get replayed;
        # exported, removed or modified parameters stay with the file.
        local -A pa=("${(@)pnow}") pb=("${(@)p0}")
        for n in "${(@k)pa}" "${(@k)pb}"
        do
          [[ "${pa[$n]-x}" == "${pb[$n]-x}" ]] && continue
          if (( ! $+pb[$n] )) && [[ "${parameters[$n]}" != *(export|special|readonly|tied)* ]]
          then
            replay+=("${$(typeset -p -- "$n")/#typeset /typeset -g }")
            continue
          fi
          effect="param $n"
          break
        done
      fi
    fi
    if [[ "$effect" == 0 ]]
    then
      for n v in "${(@kv)options}"
      do
        [[ "$v" == "${o0[$n]}" ]] || { effect="setopt $n"; break }
      done
    fi

    (( ${#inherited_exports} )) && typeset -gx -- "${inherited_exports[@]}"
    file_reason[$file]=$effect
    [[ "$effect" == 0 ]]; file_effect[$file]=$(( $? ))
    file_replay[$file]="${(pj:\0:)replay}"
    file_funcs[$file]="${(j: :)defined}"
    for n in "${defined[@]}"
    do
      owner[$n]="$file"
    done
  done

  unfunction compdef zle bindkey zstyle zmodload trap sched zsh::_zlp-param-snapshot 2>/dev/null

  local -a names=() restub=() lines=()
  local -A eager_defined
  for file in "${files[@]}"
  do
    if (( file_effect[$file] ))
    then
      lines+=("zsh::source-plugin ${(q)file}")
      (( eager_count++ ))
      for n in ${=file_funcs[$file]}
      do
        eager_defined[$n]=1
      done
    elif [[ -n "${file_replay[$file]}" ]]
    then
      lines+=("${(@ps:\0:)file_replay[$file]}")
    fi
  done
  for n file in "${(@kv)owner}"
  do
    (( file_effect[$file] )) && continue
    names+=("$n")
    (( $+eager_defined[$n] )) && restub+=("$n")
  done
  names=("${(@o)names}")

  # Write the parsed functions as they are in memory: no text round trip.
  if (( ${#names} ))
  then
    zcompile -c "$build/functions.zwc" "${names[@]}" || return 1
  fi

  # head.zsh: register the autoload stubs (fast). body: the remaining
  # commands in plugin order (replayed aliases/compdefs/parameters and the
  # files sourced as before), NUL-separated so the interactive loader can
  # run them one per idle tick. Functions that an eager file redefined are
  # re-stubbed by zsh::local-plugins-finish (__zlp_restub).
  {
    print -r -- "# Generated by zsh::local-plugins-compile; do not edit."
    print -r -- "typeset -ga __zlp_names=(${(j: :)${(@q)names}})"
    print -r -- "typeset -ga __zlp_restub=(${(j: :)${(@q)restub}})"
    print -r -- '() {'
    print -r -- '  local -a defined=("${(@k)functions}")'
    print -r -- '  local -a clash=("${(@)__zlp_names:*defined}")'
    print -r -- '  (( ${#clash} )) && unfunction -- "${clash[@]}"'
    print -r -- '}'
    print -r -- "fpath=(${(q)build}/functions.zwc \$fpath)"
    print -r -- '(( ${#__zlp_names} )) && autoload -Uz -- "${__zlp_names[@]}"'
    print -r -- 'unset __zlp_names'
  } >| "$build/head.zsh"
  print -rn -- "${(pj:\0:)lines}" >| "$build/body"

  print -r -- "${#files} files, ${#names} autoloaded functions, $eager_count files sourced" >| "$build/summary"
  for file in "${files[@]}"
  do
    (( file_effect[$file] )) && print -r -- "${file#${zsh_local_plugin_dirs[1]}/}: ${file_reason[$file]}"
  done >| "$build/eager-reasons"
  print -r -- "$key" >| "$build/key"

  # Index: build per environment fingerprint. Keep other environments'
  # builds of the same plugin set (at most 8), replace this one's.
  zmodload -F zsh/mapfile p:mapfile
  local -a idx=() old_idx=()
  [[ -r "$base/index" ]] && old_idx=("${(@ps:\0:)mapfile[$base/index]}")
  idx=("${build:t}" "$fp")
  integer i
  for (( i = 1; i < ${#old_idx} && ${#idx} < 16; i += 2 ))
  do
    [[ "${old_idx[i+1]}" != "$fp" && -r "$base/${old_idx[i]}/key" ]] || continue
    [[ "${mapfile[$base/${old_idx[i]}/key]%$'\n'}" == "$key" ]] || continue
    idx+=("${old_idx[i]}" "${old_idx[i+1]}")
  done
  print -rn -- "${(pj:\0:)spec}" >| "$base/spec.tmp" && mv -f -- "$base/spec.tmp" "$base/spec" || return 1
  print -rn -- "${(pj:\0:)idx}" >| "$base/index.tmp" && mv -f -- "$base/index.tmp" "$base/index" || return 1
  print -rl -- "${spec[@]}" >| "$build/spec.txt"

  # Running shells keep autoloading from the build they started with, so
  # only prune builds that left the index two weeks ago.
  local old
  for old in "$base"/build.*(N/mw+14)
  do
    (( ${idx[(Ie)${old:t}]} )) || rm -rf -- "$old"
  done
  rm -f -- "$base/current"
}

# reply=spec entries for what the given files' top-level code reads.
zsh::_zlp-spec() {
  setopt localoptions noaliases extendedglob
  zmodload -F zsh/mapfile p:mapfile
  # Per-session variables: only whether they're set matters.
  local presence='(SSH_CONNECTION|SSH_CLIENT|SSH_TTY|SSH_AUTH_SOCK|TMUX|TMUX_PANE|WINDOWID|DISPLAY|WAYLAND_DISPLAY|TTY|GPG_TTY|TERM_SESSION_ID|KITTY_WINDOW_ID|WEZTERM_PANE|XDG_SESSION_ID)'
  # Normalised by the compiler, internal, or not environment.
  local ignore='(commands|functions|aliases|galiases|saliases|options|parameters|builtins|reswords|modules|widgets|keymaps|words|path|PATH|fpath|ZHJ|ZHJ_MODE|NO_PLUGINS|NO_COMPLETIONS|NO_LOCAL_PLUGINS|NO_INSTANT_PROMPT|RANDOM|SECONDS|LINENO|EPOCHREALTIME|EPOCHSECONDS|PWD|OLDPWD|SHLVL|PPID|_|status|pipestatus|reply|REPLY|match|MATCH)'
  local file line text name
  local -a keep refs cmds
  local -A seen
  integer skip dynamic=0
  for file in "$@"
  do
    unfunction __zlp_file 2>/dev/null
    eval "function __zlp_file {"$'\n'"${mapfile[$file]}"$'\n'"}" 2>/dev/null || { dynamic=1; continue }
    # Printed back: top-level statements are indented one tab, nested
    # functions print as "\tNAME () {" ... "\t}".
    keep=() skip=0
    for line in "${(@f)functions[__zlp_file]}"
    do
      if (( skip ))
      then
        [[ "$line" == $'\t}' ]] && skip=0
        continue
      fi
      if [[ "$line" == $'\t'[^$'\t'' ']##' () {' ]]
      then
        skip=1
        continue
      fi
      keep+=("$line")
    done
    text="${(F)keep}"
    # Command-position lookups we can't attribute to a name: whole PATH.
    [[ "$text" =~ '(^|[[:space:];&|(!])(whence|type|hash|command[[:space:]]+-[vV])[[:space:]]' ]] && dynamic=1
    cmds=(${(M)${(f)${text//(#b)commands\[([^\]]#)\]/$'\n'@@$match[1]$'\n'}}:#@@*})
    for name in ${cmds#@@}
    do
      [[ "$name" == [A-Za-z0-9_.+-]## ]] || { dynamic=1; continue }
      seen[c:$name]=1
    done
    refs=(${(M)${(f)${text//(#b)(\$\{[\#+=~^]#|\$[\#+]#)([A-Za-z_][A-Za-z0-9_]#)/$'\n'@@$match[2]$'\n'}}:#@@*})
    for name in ${refs#@@}
    do
      [[ "$name" == ${~ignore} ]] && continue
      if [[ "$name" == ${~presence} ]]
      then
        seen[p:$name]=1
      else
        seen[v:$name]=1
      fi
    done
  done
  unfunction __zlp_file 2>/dev/null
  reply=(${(ko)seen})
  (( dynamic )) && reply+=(P)
}
