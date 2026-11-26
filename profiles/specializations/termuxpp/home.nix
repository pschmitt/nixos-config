{
  config,
  hostname,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  termuxpp = inputs.termuxpp.lib.nixpp.packagesFor pkgs;
  inherit (termuxpp) nixpp;
  tmad = "${lib.getExe pkgs.tmux} -f ${lib.escapeShellArg "${config.xdg.configHome}/tmux/tmux.conf"} -u new-session -A -D -s main";
  readTripleTapCommand =
    pkgs.writers.writePython3 "termuxpp-triple-tap-command"
      {
        libraries = [ pkgs.python3Packages.pyyaml ];
      }
      ''
        import sys

        import yaml

        with open(sys.argv[1], encoding="utf-8") as source:
            config = yaml.safe_load(source) or {}
        triple = config.get("gestures", {}).get("tap", {}).get("triple", {})
        if str(triple.get("action", "")).casefold() == "send-keys":
            sys.stdout.write(str(triple.get("command", "")))
      '';
in
{
  imports = [
    ../../../modules/home-manager/termuxpp/adb-shell.nix
    ../../../modules/home-manager/termuxpp/properties.nix
    ../../../modules/home-manager/termuxpp/appearance.nix
    ../../../modules/home-manager/termuxpp/cache.nix
    ../../../modules/home-manager/termuxpp/gpg.nix
    ../../../modules/home-manager/termuxpp/operations.nix
    ../../../modules/home-manager/termuxpp/eza.nix
    ../../../modules/home-manager/termuxpp/rworker.nix
    ../../../modules/home-manager/termuxpp/package-set.nix
    ../../../modules/home-manager/termuxpp/permissions.nix
    ../../../modules/home-manager/termuxpp/self-update.nix
    ../../../modules/home-manager/termuxpp/bridge.nix
    ../../../modules/home-manager/termuxpp/git-wiit.nix
    ../../../modules/home-manager/termuxpp/lifecycle.nix
    ../../../modules/home-manager/termuxpp/mani.nix
    ../../../modules/home-manager/termuxpp/nightly.nix
    ../../../modules/home-manager/termuxpp/native-services.nix
    ../../../modules/home-manager/termuxpp/sops.nix
    ../../../modules/home-manager/termuxpp/yadm.nix
    ../../../modules/dotfiles.nix
    ../../../modules/domains.nix
    ../../../modules/main-user.nix
    ../../../home-manager/host.nix
    ../../../home-manager/bitwarden.nix
    ../../../home-manager/devel/nix-tools.nix
    ../../../home-manager/nix-index-database.nix
    ../../../home-manager/cli/bat.nix
    ../../../home-manager/cli/fd.nix
    ../../../home-manager/cli/ripgrep.nix
    ../../../home-manager/cli/nvim
    ../../../home-manager/cli/ssh-tools.nix
    inputs.nixos-config-private.homeManagerModules.sshClient
    inputs.nixos-config-private.homeManagerModules.zshFiles
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
    ../../../home-manager/cli/git.nix
    ../../../home-manager/cli/tmux
    ../../../home-manager/cli/zsh/config/runtime.nix
    ../../../home-manager/cli/zsh/files
    ../../../home-manager/cli/zsh/plugins
    ../../../home-manager/cli/workstation-tools.nix
    ../../../home-manager/cli/zsh/tools/termux/home-assistant-cli.nix
    ../../../home-manager/gui/home-assistant-secrets.nix
  ];

  dotfiles.sshClient.disableMultiplexing = true;

  nixpp = {
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
      config.nix.package
      termuxpp.termuxpp-rish
      termuxpp.termuxpp-storage
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
        less
        ncurses
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
    # OpenSSH starts Bash; tmux panes run zsh
    configFile."tmux/local.conf".text = ''
      set -g default-shell ${pkgs.zsh}/bin/zsh
    '';
  };
  # The TermuxPP app's config.yaml (formerly termuxpp.properties in yadm),
  # in its grouped layout. The whole file is written on activation; edits in
  # the app's settings do not persist.
  nixpp.settings = {
    appearance = {
      # Dark theme (formerly use-black-ui).
      night-mode = "true";
      toast-position = "top-right";
    };
    terminal = {
      bell = "vibrate";
      open-url-on-click = true;
    };
    sessions = {
      create-on-single-session-switch = true;
      # The session and tmux window pickers open in the middle of the
      # terminal, above the keyboard while it is shown.
      picker-position = "terminal";
    };
    # The active tmux window as a filled accent pill.
    tmux.sidebar.style = "rounded";
    keyboard = {
      back-key = "back";
      shortcuts = {
        create-session = "disabled";
        previous-session = "ctrl + 1";
        next-session = "ctrl + 2";
        rename-session = "ctrl + 3";
      };
    };
    extra-keys = {
      keys = [
        [
          "ESC"
          {
            key = "/";
            popup = "BACKSLASH";
          }
          {
            key = "-";
            popup = "_";
          }
          "HOME"
          {
            key = "UP";
            popup = "PGUP";
          }
          "END"
          "PGUP"
          "|"
        ]
        [
          "TAB"
          {
            key = "CTRL";
            popup = "SHIFT";
          }
          "ALT"
          {
            key = "LEFT";
            popup = "HOME";
          }
          {
            key = "DOWN";
            popup = "PGDN";
          }
          {
            key = "RIGHT";
            popup = "END";
          }
          "PGDN"
          {
            key = "BKSP";
            popup = "DEL";
          }
        ]
      ];
      # Latched modifiers and pressed keys in the logo palette.
      active = {
        text-color = "#D8B4FE";
        background-color = "#3B1D6A";
      };
      corner-radius = 8;
      # Extra keys row: finger to the right = previous session, to the left =
      # next session (the default), further to the right = new session.
      swipe = {
        left.action = "previous-session";
        long-left.action = "new-session";
      };
    };
    gestures = {
      # Gesture feedback pills in the middle of the screen.
      feedback.position = "center";
      # Focus an existing fnuc tmux client before asking the local zsh prompt
      # to attach.
      tap.triple = {
        focus-title = "^(!?t:fnuc([.]lan)?:|tmux(:[^@ ]+)?@fnuc([.]lan)?( |$))";
        action = "send-keys";
        keys = "CTRL SHIFT F12";
        command = "ssh::tmux f";
      };
      # Swiping right with two fingers opens the session sidebar.
      swipe.two-finger.right.action = "open-sidebar";
    };
    integrations.allow-external-apps = true;
  };
  # The scripts the app runs for shared files and URLs (formerly in yadm), and a
  # README. The app reads ~/.config/termuxpp outside the guest, so install real
  # files, not store links (see config-README.md).
  home.activation.termuxppScripts = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    run ${pkgs.coreutils}/bin/install -D -m 0644 ${./config-README.md} \
      ${config.xdg.configHome}/termuxpp/README.md
    run ${pkgs.coreutils}/bin/install -D -m 0755 ${./bin/termux-file-editor} \
      ${config.xdg.configHome}/termuxpp/bin/termux-file-editor
    run ${pkgs.coreutils}/bin/install -D -m 0755 ${./bin/termux-url-opener} \
      ${config.xdg.configHome}/termuxpp/bin/termux-url-opener
  '';
  # The ADB shell listener runs only on the home Wi-Fi networks; their names
  # stay in SOPS (each phone's own list).
  nixpp.adbShell.allowedSsidsFile = config.sops.secrets."wifi/home-ssids".path;

  sops = {
    secrets = {
      "wifi/home-ssids" = { };
      "nix/github_token".sopsFile = config.host.sopsDefaultFile;
      "glab/git.wiit.one/token".sopsFile = config.host.sopsDefaultFile;
    };
    # Also pushed to rworkers (rworker setup nix), which then fetch private
    # flake inputs themselves.
    templates."nix-access-tokens".content = ''
      access-tokens = github.com=${config.sops.placeholder."nix/github_token"} git.wiit.one=PAT:${
        config.sops.placeholder."glab/git.wiit.one/token"
      }
    '';
  };
  nix = {
    enable = true;
    package = lib.mkDefault pkgs.nix;
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
    neovim.nightly.enable = false;
    nixvim = {
      clipboard.providers.wl-copy.enable = false;
      lsp.servers = {
        copilot.enable = false;
        nil_ls.enable = false;
        nixd.enable = true;
      };
      extraPackages = [ pkgs.statix ];
      extraConfigLua = ''
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
              local properties="${config.xdg.configHome}/termuxpp/config.yaml"
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
