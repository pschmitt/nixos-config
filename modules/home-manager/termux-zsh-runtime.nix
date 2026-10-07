{
  config,
  lib,
  ...
}:
{
  imports = [
    ../../home-manager/cli/zsh/config/runtime.nix
    ../../home-manager/cli/zsh/plugins/local-path.nix
    ../../home-manager/cli/zsh/plugins/local-yadm.nix
  ];

  programs.zsh = {
    setOptions = [ "NO_GLOBAL_RCS" ];

    sessionVariables = {
      GITSTATUS_AUTO_INSTALL = "0";
      POWERLEVEL9K_DISABLE_CONFIGURATION_WIZARD = "true";
      ZSH_CACHE_DIR = "${config.xdg.cacheHome}/zsh";
    };

    envExtra = lib.mkAfter ''
      export LC_ALL="''${LC_ALL:-en_US.UTF-8}"
      unset VIMINIT

      if [[ -n "''${TERM_SSH_CLIENT:-}" ]] && infocmp "''${TERM_SSH_CLIENT}" &>/dev/null
      then
        export TERM="$TERM_SSH_CLIENT"
      fi

      fpath=("$ZDOTDIR/completions" $fpath)

      if [[ -z "''${NETWORK_LOCATION:-}" && -r ${lib.escapeShellArg "${config.xdg.cacheHome}/network-location.txt"} ]]
      then
        NETWORK_LOCATION="$(<${lib.escapeShellArg "${config.xdg.cacheHome}/network-location.txt"})"
      fi

      export XDG_DATA_DIRS="$PREFIX/share:''${XDG_DATA_DIRS:-/usr/share}"
      [[ -d ${lib.escapeShellArg "${config.xdg.cacheHome}/zsh"} ]] || mkdir -p -- ${lib.escapeShellArg "${config.xdg.cacheHome}/zsh"}
      export ZSH_COMPDUMP=${lib.escapeShellArg "${config.xdg.cacheHome}/zsh/zcompdump-termux"}-''${TERMUX_GENERATION:t}

      # Match the regular yadm .zshenv while keeping private overrides at runtime.
      if [[ -r "$XDG_CONFIG_HOME/zsh/zshenv.private" ]]
      then
        source "$XDG_CONFIG_HOME/zsh/zshenv.private"
      fi

      # Keep generation commands ahead of user-local tools after private Zsh
      # startup files have adjusted PATH.
      typeset -U path
      path=("$TERMUX_GENERATION/bin" "$PREFIX/bin" $path)
      rehash
    '';

    initContent = lib.mkMerge [
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
      '')
      (lib.mkOrder 1540 ''
        if [[ -o interactive && -z "''${NO_PLUGINS:-}" ]]
        then
          zsh::load-local-plugins
        fi
      '')
      (lib.mkOrder 2000 ''
        # The login profile may prepend user-local directories after .zshenv.
        # Restore deterministic package precedence once all startup files ran.
        typeset -U path
        path=("''${(@)path:#$TERMUX_GENERATION/bin}")
        path=("''${(@)path:#$PREFIX/bin}")
        path=("$TERMUX_GENERATION/bin" "$PREFIX/bin" $path)
        rehash
      '')
    ];
  };
}
