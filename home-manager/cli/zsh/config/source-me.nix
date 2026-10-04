{
  config,
  pkgs,
  ...
}:
let
  termuxMode = config.termux.enable or false;
  sourceMe =
    if termuxMode then
      ''
        if (( $+commands[vault] ))
        then
          complete -C "$commands[vault]" vault
        fi
      ''
    else
      ''
        # bashcompinit is not needed here since we already do this in zinit
        # autoload -U +X bashcompinit && bashcompinit
        # FIXME openbao is broken as of 2026-01-09
        # https://github.com/NixOS/nixpkgs/pull/478004
        # complete -C "${pkgs.openbao}/bin/bao" bao
        complete -C "${pkgs.vault}/bin/vault" vault

        if (( $+commands[rbw] ))
        then
          typeset rbw_bin rbw_prefix
          rbw_bin="''${commands[rbw]:A}"
          rbw_prefix="''${rbw_bin:h:h}"

          if [[ -r "''${rbw_prefix}/share/zsh/site-functions/_rbw" ]]
          then
            source "''${rbw_prefix}/share/zsh/site-functions/_rbw"
          elif [[ -r "''${rbw_prefix}/share/bash-completion/completions/rbw" ]]
          then
            source "''${rbw_prefix}/share/bash-completion/completions/rbw"
          elif [[ -r "''${rbw_prefix}/share/bash-completion/completions/rbw.bash" ]]
          then
            source "''${rbw_prefix}/share/bash-completion/completions/rbw.bash"
          fi
        fi
      '';
in
{
  xdg.configFile."zsh/completions/source-me.zsh".text = sourceMe;
}
