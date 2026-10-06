{ config, lib, ... }:
let
  localPluginDir = "${config.xdg.configHome}/zsh/plugins/local";
  termuxMode = config.termux.enable or false;
  sourcePlugin = if termuxMode then ''source "$source_file" ""'' else ''source "$source_file"'';
in
{
  programs.zsh.initContent = lib.mkMerge [
    (lib.mkOrder 800 ''
      zsh::prompt-plugins-enabled() {
        [[ -z "''${NO_PLUGINS:-}" &&
          -z "''${NO_PROMPT_PLUGINS:-}" &&
          -z "''${ZINIT_SKIP_PROMPT_PLUGINS:-}" ]]
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
        [[ "$source_file" == "${localPluginDir}/"* ]] && origin=local
        started=$EPOCHREALTIME
        ${sourcePlugin}
        result=$?
        elapsed_ms=$(( (EPOCHREALTIME - started) * 1000 ))
        printf 'zsh-plugin %-5s %-32s %8.3f ms\n' "$origin" "$label" "$elapsed_ms" >&2
        return "$result"
      }
    '')
    (lib.mkOrder 1350 ''
      # The yadm-managed local plugins (~350 files) dominate startup. Load them
      # synchronously for scripts (eval mode, zhj, reloads) and asynchronously,
      # one file per idle zle tick, in interactive shells (see below).
      # Functions to run once the local plugins are loaded (sync or async).
      typeset -ga zsh_after_local_plugins

      zsh::local-plugin-files() {
        reply=(
          "${config.xdg.configHome}/zsh/plugins/local"/*.zsh(N)
          "${config.xdg.configHome}/zsh/plugins/local/work"/*.zsh(N)
          "${config.xdg.configHome}/zsh/plugins/local/99-after"/*.zsh(N)
        )
        reply=("''${(@)reply:#*/zinit.zsh}")
      }

      zsh::local-plugins-prepare() {
        # This system alias prevents the unchanged local fallback function
        # from parsing in Zsh when docker-compose is not installed.
        if (( $+aliases[docker-compose] )) && (( ! $+commands[docker-compose] ))
        then
          unalias docker-compose
        fi
      }

      zsh::local-plugins-finish() {
        if (( $+functions[zsh::override-local-path] ))
        then
          zsh::override-local-path
        fi

        if (( $+functions[zsh::override-local-yadm] ))
        then
          zsh::override-local-yadm
        fi

        if [[ "''${TERMUX_RUN_MODE:-}" != ci && -z "''${ZSH_SECRETS_SOURCED:-}" ]]
        then
          typeset -g ZSH_SECRETS_SOURCED=1
          [[ -r "${config.xdg.configHome}/zsh/secrets.zsh" ]] && source "${config.xdg.configHome}/zsh/secrets.zsh" 2>/dev/null
        fi

        if [[ "''${TERMUX_NATIVE_YADM_CONFIG:-}" == 1 ]]
        then
          typeset -g TERMUX_NATIVE_USER_PLUGINS_READY=1
        fi

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
      }

      zsh::source-local-plugins() {
        [[ -n "''${NO_LOCAL_PLUGINS:-}" ]] && return 0
        local -a reply
        local file
        zsh::local-plugin-files
        zsh::local-plugins-prepare
        for file in "''${reply[@]}"
        do
          zsh::source-plugin "$file"
        done
        zsh::local-plugins-finish
      }

      # Interactive shells: queue the files and source them from zle idle
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

        local -a reply
        zsh::local-plugin-files
        typeset -ga __zsh_local_plugin_queue=("''${reply[@]}")
        typeset -g __zsh_local_plugin_log="''${ZSH_CACHE_DIR:-${config.xdg.cacheHome}/zsh}/local-plugins.log"
        : >| "$__zsh_local_plugin_log"
        zsh::local-plugins-prepare
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

        while (( ''${#__zsh_local_plugin_queue} && ! KEYS_QUEUED_COUNT && ! PENDING ))
        do
          zsh::source-plugin "''${__zsh_local_plugin_queue[1]}" >>"$__zsh_local_plugin_log" 2>&1
          shift __zsh_local_plugin_queue
        done

        if (( ''${#__zsh_local_plugin_queue} ))
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
