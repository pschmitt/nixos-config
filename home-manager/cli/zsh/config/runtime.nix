{ config, lib, ... }:
let
  localPluginBundle = "${config.xdg.configHome}/zsh/plugins/local.zsh";
  sourcePlugin = ''source "$source_file"'';
in
{
  programs.zsh.initContent = lib.mkMerge [
    (lib.mkOrder 800 ''
      zsh::prompt-plugins-enabled() {
        [[ -z "''${NO_PLUGINS:-}" &&
          -z "''${NO_PROMPT_PLUGINS:-}" ]]
      }

      # Plugins run as functions inside these helpers, so the helpers only
      # use __zpl_* names: a plugin's global assignment (name=...) must not
      # land in a helper's local.
      zsh::run-local-plugin() {
        local __zpl_fn="$1" __zpl_status
        if [[ -z "''${ZSH_PLUGIN_TIMINGS:-}" ]] || ! zmodload zsh/datetime 2>/dev/null
        then
          "$__zpl_fn"
          __zpl_status=$?
        else
          local -F 3 __zpl_started __zpl_elapsed
          __zpl_started=$EPOCHREALTIME
          "$__zpl_fn"
          __zpl_status=$?
          __zpl_elapsed=$(( (EPOCHREALTIME - __zpl_started) * 1000 ))
          printf 'zsh-plugin %-5s %-32s %8.3f ms\n' local "''${__zpl_fn#zpl::}" "$__zpl_elapsed" >&2
        fi
        unfunction -- "$__zpl_fn" 2>/dev/null
        return "$__zpl_status"
      }

      # Interactive (zle) shells run the editing plugins (suggestions,
      # highlighting, ...) after the first prompt, behind the local plugins
      # (config/runtime.nix, order 1350); other shells load them right away.
      typeset -ga zsh_deferred_plugins
      zsh::defer() {
        if [[ -o zle && -z "''${ZSH_SYNC_LOCAL_PLUGINS:-}" && -z "''${NO_LOCAL_PLUGINS:-}" ]]
        then
          zsh_deferred_plugins+=("$1")
        else
          zsh::run-local-plugin "$1"
        fi
      }

      zsh::source-plugin() {
        local source_file="$1"
        local label="''${2:-''${source_file:t}}"
        if [[ -z "''${ZSH_PLUGIN_TIMINGS:-}" ]] || ! zmodload zsh/datetime 2>/dev/null
        then
          ${sourcePlugin}
          return $?
        fi

        local result origin=nix
        local -F 3 started elapsed_ms
        if [[ "$source_file" == "${config.xdg.configHome}/zsh/static/"* ]]
        then
          origin=local
        fi
        started=$EPOCHREALTIME
        ${sourcePlugin}
        result=$?
        elapsed_ms=$(( (EPOCHREALTIME - started) * 1000 ))
        printf 'zsh-plugin %-5s %-32s %8.3f ms\n' "$origin" "$label" "$elapsed_ms" >&2
        return "$result"
      }
    '')
    (lib.mkOrder 1350 ''
      # The local plugins are functions in one zcompiled file (../files),
      # run in order. Scripts (eval mode, zhj, reloads) run them all at once;
      # interactive shells run one per idle zle tick (see below).
      # Functions to run once the local plugins are loaded (sync or async).
      typeset -ga zsh_after_local_plugins

      # __zpl_plugins=(plugin functions in load order), from the bundle.
      zsh::local-plugin-list() {
        typeset -ga __zpl_plugins=()
        [[ -r "${localPluginBundle}" ]] || return 1
        source "${localPluginBundle}" || return 1
        __zpl_manifest
        unfunction __zpl_manifest
      }


      zsh::local-plugins-finish() {
        if (( $+functions[zsh::apply-plugin-overrides] ))
        then
          zsh::apply-plugin-overrides
        fi

        if [[ -o interactive && -z "''${NO_COMPLETIONS:-}" ]] && (( $+functions[__init_custom_completions] ))
        then
          __init_custom_completions
        fi

        local hook
        for hook in $zsh_after_local_plugins
        do
          (( $+functions[$hook] )) && "$hook"
        done

        typeset -g ZSH_LOCAL_PLUGINS_LOADED=1

        # Writable local overrides run last, after the managed plugins
        # and their overrides, in both synchronous and deferred shells.
        local static_file
        for static_file in "${config.xdg.configHome}/zsh/static/"*.zsh(N)
        do
          zsh::source-plugin "$static_file"
        done
      }

      alias zsrclocal=zsh::source-local-plugins

      zsh::source-local-plugins() {
        [[ -n "''${NO_LOCAL_PLUGINS:-}" ]] && return 0
        local __zpl_next
        zsh::local-plugin-list
        for __zpl_next in "''${__zpl_plugins[@]}"
        do
          zsh::run-local-plugin "$__zpl_next"
        done
        unset __zpl_plugins
        zsh::local-plugins-finish
      }

      # Interactive shells: queue the plugins and run them from zle idle
      # callbacks (the zsh-defer technique, without its `emulate -L zsh`, so
      # plugins keep the user's options and their setopts persist). Loading
      # pauses while keys are pending, so typing at the first prompt stays
      # responsive. Plugin output goes to a log instead of over the prompt.
      zsh::load-local-plugins() {
        [[ -n "''${NO_LOCAL_PLUGINS:-}" ]] && return 0
        if [[ ! -o zle || -n "''${ZSH_SYNC_LOCAL_PLUGINS:-}" ]]
        then
          zsh::source-local-plugins
          return
        fi

        zsh::local-plugin-list
        typeset -ga __zsh_local_plugin_queue=("''${__zpl_plugins[@]}")
        unset __zpl_plugins
        typeset -g __zsh_local_plugin_log="''${ZSH_CACHE_DIR:-${config.xdg.cacheHome}/zsh}/local-plugins.log"
        : >| "$__zsh_local_plugin_log"
        zsh::local-plugins-schedule
      }

      zsh::local-plugins-schedule() {
        local fd
        exec {fd}</dev/null
        zle -F "$fd" zsh::local-plugins-resume
      }

      zsh::local-plugins-resume() {
        zle -F "$1"
        exec {1}<&-

        while (( ! KEYS_QUEUED_COUNT && ! PENDING ))
        do
          # The deferred editing plugins (zsh::defer) run after the local ones.
          if (( ! ''${#__zsh_local_plugin_queue} && ''${#zsh_deferred_plugins} ))
          then
            __zsh_local_plugin_queue=("''${zsh_deferred_plugins[@]}")
            zsh_deferred_plugins=()
          fi
          (( ''${#__zsh_local_plugin_queue} )) || break
          zsh::run-local-plugin "''${__zsh_local_plugin_queue[1]}" >>"$__zsh_local_plugin_log" 2>&1
          shift __zsh_local_plugin_queue
        done

        if (( ''${#__zsh_local_plugin_queue} || ''${#zsh_deferred_plugins} ))
        then
          zsh::local-plugins-schedule
          return 0
        fi

        zsh::local-plugins-finish >>"$__zsh_local_plugin_log" 2>&1
        unset __zsh_local_plugin_queue

        # Let the prompt, suggestions and highlighting pick up what loaded.
        local hook
        for hook in $precmd_functions
        do
          (( $+functions[$hook] )) && "$hook"
        done
        (( $+functions[_zsh_autosuggest_bind_widgets] )) && _zsh_autosuggest_bind_widgets
        (( $+_ZSH_HIGHLIGHT_PRIOR_BUFFER )) && _ZSH_HIGHLIGHT_PRIOR_BUFFER=
        zle && zle reset-prompt
        if [[ -s "$__zsh_local_plugin_log" ]]
        then
          zle && zle -M "local plugins printed output: $__zsh_local_plugin_log"
        fi
        return 0
      }

    '')
    (lib.mkOrder 1600 ''
      zsh::reload-runtime() {
        zsh::source-local-plugins
        (( $+functions[wayland::export-display] )) && wayland::export-display &>/dev/null
        [[ -z "$SSH_TTY" ]] && (( $+functions[tmux::source-environment] )) && tmux::source-environment
        (( $+functions[network-location::from-file] )) && NO_LOCATION_UPDATE=1 network-location::from-file
      }

      TRAPUSR1() {
        zsh::reload-runtime
        rehash
      }

      TRAPUSR2() {
        (( $+functions[network-location::from-file] )) && network-location::from-file
      }
    '')
  ];
}
