{
  config,
  hostname,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  nixpp = pkgs.callPackage ../../../pkgs/nixpp { };
  tmad = "${lib.getExe pkgs.tmux} -f ${lib.escapeShellArg "${config.xdg.configHome}/tmux/tmux.conf"} -u new-session -A -D -s main";
  readTripleTapCommand =
    pkgs.writers.writePython3 "termuxpp-triple-tap-command"
      {
        libraries = [ pkgs.python3Packages.javaproperties ];
      }
      ''
        import sys

        import javaproperties

        with open(sys.argv[1], encoding="utf-8") as source:
            props = javaproperties.load(source)
        if props.get("terminal-triple-tap-action", "").casefold() == "send-keys":
            sys.stdout.write(props.get("terminal-triple-tap-command", ""))
      '';
in
{
  imports = [
    ../../../modules/home-manager/termuxpp/appearance.nix
    ../../../modules/home-manager/termuxpp/cache.nix
    ../../../modules/home-manager/termuxpp/gpg.nix
    ../../../modules/home-manager/termuxpp/operations.nix
    ../../../modules/home-manager/termuxpp/eza.nix
    ../../../modules/home-manager/termuxpp/rworker.nix
    ../../../modules/home-manager/termuxpp/package-set.nix
    ../../../modules/home-manager/termuxpp/bridge.nix
    ../../../modules/home-manager/termuxpp/lifecycle.nix
    ../../../modules/home-manager/termuxpp/nightly.nix
    ../../../modules/home-manager/termuxpp/sops.nix
    ../../../modules/home-manager/termuxpp/yadm.nix
    ../../../modules/dotfiles.nix
    ../../../modules/domains.nix
    ../../../modules/main-user.nix
    ../../../home-manager/host.nix
    ../../../home-manager/bitwarden.nix
    ../../../home-manager/devel/nix-tools.nix
    ../../../home-manager/nix-index-database.nix
    ../../../home-manager/termux-options.nix
    ../../../home-manager/cli/bat.nix
    ../../../home-manager/cli/fd.nix
    ../../../home-manager/cli/ripgrep.nix
    ../../../home-manager/cli/nvim
    ../../../home-manager/cli/ssh-tools.nix
    inputs.nixos-config-private.homeManagerModules.sshClient
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
    ../../../home-manager/cli/zsh/tools/termux/home-assistant-cli.nix
    ../../../home-manager/gui/home-assistant-secrets.nix
  ];

  dotfiles.sshClient.disableMultiplexing = true;

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
    packages = [
      (pkgs.callPackage ../../../pkgs/nixpp/rish.nix { })
      (pkgs.callPackage ../../../pkgs/nixpp/storage.nix { })
    ]
    ++ builtins.attrValues {
      inherit (pkgs) iputils;
      inherit (pkgs)
        bashInteractive
        cacert
        coreutils
        curl
        diffutils
        findutils
        fping
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

  # OpenSSH starts the guest account's Bash login shell from /etc/passwd.
  home.file.".bash_profile".text = ''
    if [[ -n ''${SSH_CONNECTION:-} && $- == *i* ]]
    then
      exec "$HOME/.nix-profile/bin/zsh" -l
    fi
  '';
  dotfiles.zsh.nixShell.default = true;
  xdg = {
    enable = true;
    configFile."zsh/completions/_nixpp".source = "${nixpp}/share/zsh/site-functions/_nixpp";
    configFile."nvim/lua/plugins/full-nix.lua".text = ''
      return {
        {
          "neovim/nvim-lspconfig",
          opts = { servers = { nil_ls = { enabled = false }, nixd = {} } },
        },
      }
    '';
  };
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
    rbw.settings = {
      unlockUi = "terminal";
      # rbw falls back to pinentry before it has a local vault database.
      pinentry.command = lib.mkForce (lib.getExe' pkgs.pinentry-tty "pinentry-tty");
    };
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
      shellAliases.tmad = tmad;
      envExtra = lib.mkBefore ''
        # SSH's Bash login shim execs zsh but leaves the inherited SHELL in place.
        export SHELL=${lib.escapeShellArg (lib.getExe config.programs.zsh.package)}
        export LC_ALL=C.UTF-8
        : "''${XDG_RUNTIME_DIR:=/run/user/$(id -u)}"
        export XDG_RUNTIME_DIR
        export HOST=${lib.escapeShellArg hostname}
        export HOSTNAME=$HOST
      '';
      initContent = lib.mkMerge [
        (lib.mkOrder 600 ''
          source "${config.xdg.configHome}/zsh/custom/os/home-manager/system.zsh"
          for completion_dir in \
            "${config.home.profileDirectory}/share/zsh/site-functions" \
            /run/current-system/sw/share/zsh/site-functions
          do
            if [[ -d "$completion_dir" ]]
            then
              fpath=("$completion_dir:A" $fpath)
            fi
          done
          unset completion_dir
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
        (lib.mkOrder 1500 ''
          if [[ -r "${config.xdg.configHome}/zsh/functions/ssh/ssh::tmux" ]]
          then
            fpath+=("${config.xdg.configHome}/zsh/functions/ssh")
            autoload -Uz ssh::tmux
          fi

          if [[ -z ''${SSH_CONNECTION:-} ]]
          then
            function _termuxpp_triple_tap_command() {
              [[ -z "$BUFFER" ]] || return 0
              local properties="${config.xdg.configHome}/termuxpp/termuxpp.properties"
              [[ -r "$properties" ]] || return 0
              local command
              command=$(${readTripleTapCommand} "$properties") || return 0
              [[ -n "$command" ]] || return 0
              BUFFER=$command
              zle accept-line
            }
            zle -N _termuxpp_triple_tap_command
            bindkey -M emacs $'\e[24;6~' _termuxpp_triple_tap_command
            bindkey -M viins $'\e[24;6~' _termuxpp_triple_tap_command
          fi
        '')
      ];
    };
  };
}
