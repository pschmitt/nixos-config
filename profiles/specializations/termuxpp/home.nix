{
  config,
  hostname,
  lib,
  pkgs,
  ...
}:
let
  tmad = "${lib.getExe pkgs.tmux} -f ${lib.escapeShellArg "${config.xdg.configHome}/tmux/tmux.conf"} -u new-session -A -D -s main";
in
{
  imports = [
    ../../../modules/home-manager/termuxpp/appearance.nix
    ../../../modules/home-manager/termuxpp/gpg.nix
    ../../../modules/home-manager/termuxpp/operations.nix
    ../../../modules/home-manager/termuxpp/eza.nix
    ../../../modules/home-manager/termuxpp/rworker.nix
    ../../../modules/home-manager/termuxpp/package-set.nix
    ../../../modules/home-manager/termuxpp/bridge.nix
    ../../../modules/home-manager/termuxpp/lifecycle.nix
    ../../../modules/home-manager/termuxpp/sops.nix
    ../../../modules/home-manager/termuxpp/yadm.nix
    ../../../modules/dotfiles.nix
    ../../../modules/domains.nix
    ../../../modules/main-user.nix
    ../../../home-manager/host.nix
    ../../../home-manager/bitwarden.nix
    ../../../home-manager/devel/nix-tools.nix
    ../../../home-manager/termux-options.nix
    ../../../home-manager/cli/bat.nix
    ../../../home-manager/cli/fd.nix
    ../../../home-manager/cli/ripgrep.nix
    ../../../home-manager/cli/nvim
    ../../../home-manager/cli/zsh/atuin.nix
    ../../../home-manager/cli/zsh/direnv.nix
    ../../../home-manager/cli/zsh/vivid.nix
    ../../../home-manager/cli/zsh/zoxide.nix
    ../../../home-manager/cli/zsh/config/core.nix
    ../../../home-manager/cli/zsh/config/zhj.nix
    ../../../home-manager/cli/zsh/plugins/local-path.nix
    ../../../home-manager/cli/zsh/plugins/local-yadm.nix
    ../../../home-manager/cli/zsh/config/portable.nix
    ../../../home-manager/cli/zsh/config/source-me.nix
    ../../../home-manager/cli/tmux
    ../../base/dotfiles/tmux.nix
    ../../../home-manager/cli/zsh/config/runtime.nix
    ../../../home-manager/cli/zsh/plugins
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
  # OpenSSH starts the guest account's Bash login shell from /etc/passwd.
  home.file.".bash_profile".text = ''
    if [[ -n ''${SSH_CONNECTION:-} && $- == *i* ]]
    then
      exec "$HOME/.nix-profile/bin/zsh" -l
    fi
  '';
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
  sops = {
    secrets."nix/github_token".sopsFile = config.host.sopsDefaultFile;
    templates."nix-access-tokens".content = ''
      access-tokens = github.com=${config.sops.placeholder."nix/github_token"}
    '';
  };
  nix = {
    enable = true;
    package = pkgs.nix;
    extraOptions = ''
      !include ${config.sops.templates."nix-access-tokens".path}
    '';
    settings = {
      experimental-features = [
        "nix-command"
        "flakes"
      ];
      max-jobs = 0;
      builders-use-substitutes = true;
      sandbox = false;
      build-users-group = "";
    };
  };
  systemd.user.startServices = false;
  news.display = "silent";
  programs = {
    home-manager.enable = true;
    rbw.package = lib.mkForce pkgs.rbw;
    rbw.settings.unlockUi = "terminal";
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
    };
    zsh = {
      enable = true;
      dotDir = "${config.xdg.configHome}/zsh-nix";
      shellAliases.tmad = tmad;
      envExtra = lib.mkBefore ''
        export LC_ALL=C.UTF-8
        : "''${XDG_RUNTIME_DIR:=/run/user/$(id -u)}"
        export XDG_RUNTIME_DIR
        export HOST=${lib.escapeShellArg hostname}
        export HOSTNAME=$HOST
      '';
      initContent = lib.mkMerge [
        (lib.mkOrder 600 ''
          source "${config.xdg.configHome}/zsh/custom/os/home-manager/system.zsh"
        '')
        (lib.mkOrder 1400 ''
          # The shared yadm tmux plugin also defines this alias.
          zsh::termuxpp-tmux-alias() {
            alias tmad=${lib.escapeShellArg tmad}
          }
          zsh_after_local_plugins+=(zsh::termuxpp-tmux-alias)

          if [[ ! -r "$HOME/.config/zsh/p10k.zsh" ]]
          then
            PROMPT='%F{${config.dotfiles.promptColor}}${hostname}%f %~ %# '
          fi
        '')
      ];
    };
  };
}
