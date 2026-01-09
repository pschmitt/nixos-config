{
  config,
  pkgs,
  ...
}:
{
  imports = [
    ./atuin.nix
    ./direnv.nix
    ./fzf.nix
    ./vivid.nix
    ./zoxide.nix
  ];

  programs.zsh = {
    enable = false;
    dotDir = "${config.xdg.configHome}/zsh/hm";
  };

  home = {
    shell.enableZshIntegration = true;

    packages = with pkgs; [
      gitstatus # used by p10k
      nix-your-shell
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
    '';

    # completions
    "zsh/completions/source-me.zsh".text = ''
      # bashcompinit is not needed here since we already do this in zinit
      # autoload -U +X bashcompinit && bashcompinit
      # FIXME openbao is broken as of 2026-01-09
      # https://github.com/NixOS/nixpkgs/pull/478004
      # complete -C "${pkgs.openbao}/bin/bao" bao
      complete -C "${pkgs.vault}/bin/vault" vault
    '';
  };
}
