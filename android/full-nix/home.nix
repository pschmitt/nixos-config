{
  config,
  hostname,
  lib,
  pkgs,
  ...
}:
{
  imports = [
    ./operations.nix
    ./eza.nix
    ./rworker.nix
    ./package-set.nix
    ./bridge.nix
    ./lifecycle.nix
    ../../modules/dotfiles.nix
    ../../modules/domains.nix
    ../../home-manager/termux-options.nix
    ../../home-manager/cli/bat.nix
    ../../home-manager/cli/fd.nix
    ../../home-manager/cli/ripgrep.nix
    ../../home-manager/cli/nvim
    ../../home-manager/cli/zsh/atuin.nix
    ../../home-manager/cli/zsh/direnv.nix
    ../../home-manager/cli/zsh/vivid.nix
    ../../home-manager/cli/zsh/zoxide.nix
    ../../home-manager/cli/zsh/config/core.nix
    ../../home-manager/cli/zsh/config/zhj.nix
    ../../home-manager/cli/zsh/plugins/local-path.nix
    ../../home-manager/cli/zsh/plugins/local-yadm.nix
    ../../home-manager/cli/zsh/config/portable.nix
    ../../home-manager/cli/zsh/config/source-me.nix
    ../../home-manager/cli/tmux
    ../../home-manager/cli/zsh/config/runtime.nix
    ../../home-manager/cli/zsh/plugins
  ];

  fullNix = {
    rworker.enable = true;
    androidBridge.enable = true;
    lifecycle.enable = true;
  };

  home = {
    username = "pschmitt";
    homeDirectory = "/home/pschmitt";
    stateVersion = "26.05";
    sessionVariables = {
      HOST = hostname;
      HOSTNAME = hostname;
      EDITOR = "nvim";
      PAGER = "less";
      NIX_CONF_DIR = "${config.xdg.configHome}/nix";
    };
    packages = builtins.attrValues {
      inherit (pkgs) iputils;
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
        jc
        jq
        less
        nix
        netcat-openbsd
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

  # The guest has no yadm-owned root startup file to select the Nix dotDir.
  home.file.".zshenv".enable = lib.mkOverride 40 true;
  dotfiles.zsh.nixShell.default = true;
  xdg.enable = true;
  xdg.configFile."nvim/lua/plugins/full-nix.lua".text = ''
    return {
      {
        "neovim/nvim-lspconfig",
        opts = { servers = { nil_ls = { enabled = false }, nixd = {} } },
      },
    }
  '';
  nix = {
    enable = true;
    package = pkgs.nix;
    settings = {
      experimental-features = [
        "nix-command"
        "flakes"
      ];
      max-jobs = 0;
      builders-use-substitutes = true;
      builders = "@${config.xdg.configHome}/nix/machines";
    };
  };
  systemd.user.startServices = false;
  news.display = "silent";
  programs = {
    home-manager.enable = true;
    neovim = {
      nightly.enable = false;
      extraPackages = [
        pkgs.nixd
        pkgs.statix
      ];
      extraLuaConfig = ''
        vim.schedule(function()
          local osc52 = require("vim.ui.clipboard.osc52")
          local function paste()
            return { vim.fn.split(vim.fn.getreg(""), "\n"), vim.fn.getregtype("") }
          end
          vim.g.clipboard = {
            name = "OSC 52",
            copy = { ["+"] = osc52.copy("+"), ["*"] = osc52.copy("*") },
            paste = { ["+"] = paste, ["*"] = paste },
          }
        end)
      '';
    };
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
      extraConfig = lib.mkAfter ''
        source-file -q "${config.xdg.configHome}/tmux/user.conf"
      '';
    };
    zsh = {
      enable = true;
      dotDir = "${config.xdg.configHome}/zsh-nix";
      envExtra = lib.mkBefore ''
        export LC_ALL=C.UTF-8
        export XDG_RUNTIME_DIR="/tmp/run"
        mkdir -p -m 700 "$XDG_RUNTIME_DIR"
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
