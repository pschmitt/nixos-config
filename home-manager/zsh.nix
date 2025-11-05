{
  config,
  inputs,
  pkgs,
  ...
}:
{
  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
    silent = true;
  };

  home.packages = with pkgs; [
    nix-your-shell
    vivid
    zoxide
  ];

  home.file = {
    "${config.xdg.configHome}/zsh/custom/os/nixos/system.zsh" = {
      text = ''
        [[ -o interactive ]] || return

        # command-not-found integration
        source ${
          inputs.nix-index-database.packages.${pkgs.stdenv.hostPlatform.system}.nix-index-with-db
        }/etc/profile.d/command-not-found.sh

        # DEPRECATED: Use wezterm.sh instead
        # source ${pkgs.vte}/etc/profile.d/vte.sh

        # FIXME the osc7 shell func produces output which p10k complains about
        # on startup (hence the WEZTERM_SHELL_SKIP_CWD)
        # WEZTERM_SHELL_SKIP_CWD=1 source ${pkgs.wezterm}/etc/profile.d/wezterm.sh

        # atuin
        source ${
          (pkgs.runCommand "atuin-init" { } ''
            mkdir -p $out/home
            HOME=$out/home ${pkgs.atuin}/bin/atuin init \
              --disable-ctrl-r \
              --disable-up-arrow \
              zsh > $out/init.zsh
            rm -rf $out/home
          '')
        }/init.zsh
        # bindkey '^[r' _atuin_search_widget

        # direnv
        source ${
          (pkgs.runCommand "direnv-init" { } ''
            mkdir -p $out
            ${pkgs.direnv}/bin/direnv hook zsh > $out/init.zsh
          '')
        }/init.zsh

        # zoxide
        source ${
          (pkgs.runCommand "zoxide-init" { } ''
            mkdir -p $out
            ${pkgs.zoxide}/bin/zoxide init zsh --no-cmd > $out/init.zsh
          '')
        }/init.zsh
        alias z=__zoxide_z
        alias zz=__zoxide_zi
      '';
    };

    # completions
    "${config.xdg.configHome}/zsh/completions/source-me.zsh" = {
      text = ''
        # bashcompinit is not needed here since we already do this in zinit
        # autoload -U +X bashcompinit && bashcompinit
        complete -C "${pkgs.openbao}/bin/bao" bao
        complete -C "${pkgs.vault}/bin/vault" vault
      '';
    };
  };
}
