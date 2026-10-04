{
  config,
  lib,
  ...
}:
{
  imports = [
    ../../home-manager/cli/zsh/config/runtime.nix
    ../../home-manager/cli/zsh/plugins/alias-tips.nix
    ../../home-manager/cli/zsh/plugins/local-compat.nix
    ../../home-manager/cli/zsh/plugins/local-path.nix
    ../../home-manager/cli/zsh/plugins/local-yadm.nix
  ];

  programs.zsh.envExtra = lib.mkAfter ''
    fpath=("$ZDOTDIR/completions" $fpath)

    typeset -gA DOMAINS
    DOMAINS[main]=${lib.escapeShellArg config.domains.main}
    DOMAINS[netbird]=${lib.escapeShellArg config.domains.netbird}
    DOMAINS[tailscale]=${lib.escapeShellArg config.domains.tailscale}

    if [[ -z "''${NETWORK_LOCATION:-}" && -r ${lib.escapeShellArg "${config.xdg.cacheHome}/network-location.txt"} ]]
    then
      NETWORK_LOCATION="$(<${lib.escapeShellArg "${config.xdg.cacheHome}/network-location.txt"})"
    fi

    export XDG_DATA_DIRS="$PREFIX/share:''${XDG_DATA_DIRS:-/usr/share}"
    mkdir -p -- ${lib.escapeShellArg "${config.xdg.cacheHome}/zsh"}
    export ZSH_CACHE_DIR=${lib.escapeShellArg "${config.xdg.cacheHome}/zsh"}
    export ZSH_COMPDUMP=${lib.escapeShellArg "${config.xdg.cacheHome}/zsh/zcompdump-termux"}-''${TERMUX_GENERATION:t}
  '';

  programs.zsh.initContent = lib.mkMerge [
    (lib.mkOrder 500 ''
      if [[ -o interactive &&
            -z "''${NO_PLUGINS:-}" &&
            -z "''${NO_PROMPT_PLUGINS:-}" &&
            -z "''${ZINIT_SKIP_PROMPT_PLUGINS:-}" &&
            -r "$XDG_CONFIG_HOME/zsh/p10k-instant-prompt.zsh" ]]
      then
        source "$XDG_CONFIG_HOME/zsh/p10k-instant-prompt.zsh"
      fi
    '')
    (lib.mkOrder 805 ''
      zsh::prompt-plugins-enabled() {
        [[ -z "''${NO_PLUGINS:-}" &&
          -z "''${NO_PROMPT_PLUGINS:-}" &&
          -z "''${ZINIT_SKIP_PROMPT_PLUGINS:-}" ]]
      }
    '')
    (lib.mkOrder 810 ''
      functions[termux::source-plugin-original]="$functions[zsh::source-plugin]"

      zsh::source-plugin() {
        local source_file="$1"
        local restore_warn_create_global=0
        local result

        if [[ "$source_file" == "''${XDG_CONFIG_HOME:-$HOME/.config}/zsh/plugins/local/"* &&
              -o warncreateglobal ]]
        then
          unsetopt warncreateglobal
          restore_warn_create_global=1
        fi

        termux::source-plugin-original "$@"
        result=$?

        if (( restore_warn_create_global ))
        then
          setopt warncreateglobal
        fi

        return "$result"
      }
    '')
    (lib.mkOrder 880 ''
      typeset -g GITSTATUS_DAEMON="$TERMUX_GENERATION/bin/gitstatusd"
      typeset -g GITSTATUS_AUTO_INSTALL=0
      typeset -g POWERLEVEL9K_DISABLE_CONFIGURATION_WIZARD=true
    '')
    (lib.mkOrder 1540 ''
      if [[ -o interactive && -z "''${NO_PLUGINS:-}" ]]
      then
        zsh::source-local-plugins
      fi
    '')
  ];
}
