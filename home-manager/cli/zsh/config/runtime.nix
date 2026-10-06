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
      zsh::source-local-plugins() {
        [[ -n "''${NO_LOCAL_PLUGINS:-}" ]] && return 0

        # This system alias prevents the unchanged local fallback function
        # from parsing in Zsh when docker-compose is not installed.
        if (( $+aliases[docker-compose] )) && (( ! $+commands[docker-compose] ))
        then
          unalias docker-compose
        fi

        local file
        for file in \
          "${config.xdg.configHome}/zsh/plugins/local"/*.zsh(N) \
          "${config.xdg.configHome}/zsh/plugins/local/work"/*.zsh(N) \
          "${config.xdg.configHome}/zsh/plugins/local/99-after"/*.zsh(N)
        do
          [[ "''${file:t}" == zinit.zsh ]] && continue
          zsh::source-plugin "$file"
        done

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
