{ lib, ... }:
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
  '';

  programs.zsh.initContent = lib.mkMerge [
    (lib.mkOrder 805 ''
      zsh::prompt-plugins-enabled() {
        [[ -z "''${NO_PLUGINS:-}" &&
          -z "''${NO_PROMPT_PLUGINS:-}" ]]
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
      if [[ -o interactive ]]
      then
        zsh::source-local-plugins
      fi
    '')
  ];
}
