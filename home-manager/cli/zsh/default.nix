{
  config,
  pkgs,
  ...
}:
{
  programs = {
    direnv = {
      enable = true;
      nix-direnv.enable = true;
      silent = true;
    };

    vivid = {
      enable = true;
      activeTheme = "one-dark";
    };

    zsh = {
      enable = false;
      dotDir = "${config.xdg.configHome}/zsh/hm";
    };
  };

  home = {
    shell.enableZshIntegration = true;

    packages = with pkgs; [
      gitstatus # used by p10k
      nix-your-shell
      zoxide
    ];
  };

  xdg.configFile = {
    "zsh/custom/os/nixos/system.zsh".text = ''
      [[ -o interactive ]] || return

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

      # vivid
      export LS_COLORS="$(cat ${
        (pkgs.runCommand "vivid-generate" { } ''
          mkdir -p $out
          ${pkgs.vivid}/bin/vivid generate ${config.programs.vivid.activeTheme} > $out/ls_colors
        '')
      }/ls_colors)"

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

    # completions
    "zsh/completions/source-me.zsh".text = ''
      # bashcompinit is not needed here since we already do this in zinit
      # autoload -U +X bashcompinit && bashcompinit
      complete -C "${pkgs.openbao}/bin/bao" bao
      complete -C "${pkgs.vault}/bin/vault" vault
    '';
  };
}
