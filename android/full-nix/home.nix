{
  config,
  hostname,
  lib,
  pkgs,
  ...
}:
{
  imports = [
    ../../modules/dotfiles.nix
    ../../modules/domains.nix
    ../../home-manager/termux-options.nix
    ../../home-manager/cli/bat.nix
    ../../home-manager/cli/eza.nix
    ../../home-manager/cli/fd.nix
    ../../home-manager/cli/ripgrep.nix
    ../../home-manager/cli/zsh/atuin.nix
    ../../home-manager/cli/zsh/direnv.nix
    ../../home-manager/cli/zsh/vivid.nix
    ../../home-manager/cli/zsh/zoxide.nix
    ../../home-manager/cli/zsh/config/base.nix
    ../../home-manager/cli/zsh/config/portable.nix
    ../../home-manager/cli/zsh/config/source-me.nix
    ../../home-manager/cli/tmux
    ../../home-manager/cli/zsh/config/runtime.nix
    ../../home-manager/cli/zsh/plugins
  ];

  home = {
    username = "nix";
    homeDirectory = "/home/nix";
    stateVersion = "26.05";
    sessionVariables = {
      HOST = hostname;
      HOSTNAME = hostname;
      EDITOR = "nvim";
      PAGER = "less";
    };
    packages = builtins.attrValues {
      inherit (pkgs)
        bashInteractive
        cacert
        coreutils
        curl
        diffutils
        findutils
        git
        gnugrep
        gnupg
        gnused
        gawk
        gnutar
        gzip
        jq
        less
        neovim
        nix
        openssh
        procps
        python3
        rbw
        rsync
        shellcheck
        sops
        ssh-to-age
        tmux
        unzip
        xz
        yadm
        zip
        ;
    };
  };

  xdg.enable = true;
  systemd.user.startServices = false;
  news.display = "silent";
  programs = {
    home-manager.enable = true;
    fzf = {
      enable = true;
      enableZshIntegration = true;
      defaultOptions = [
        "--height=80%"
        "--layout=reverse"
      ];
    };
    tmux = {
      enable = lib.mkForce true;
      shell = "${pkgs.zsh}/bin/zsh";
    };
    zsh = {
      enable = true;
      dotDir = "${config.xdg.configHome}/zsh";
      envExtra = ''
        export HOST=${lib.escapeShellArg hostname}
        export HOSTNAME=$HOST
      '';
      initContent = lib.mkMerge [
        (lib.mkOrder 600 ''
          source "${config.xdg.configHome}/zsh/custom/os/home-manager/system.zsh"
        '')
        (lib.mkOrder 1400 ''
          if [[ ! -r "$HOME/.config/zsh/p10k.zsh" ]]
          then
            PROMPT='%F{${config.dotfiles.promptColor}}${hostname}%f %~ %# '
          fi
        '')
      ];
    };
  };
}
