{
  config,
  hostname,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  pkgsTermux =
    (import ../../pkgs/termux/native/package-set.nix { inherit inputs pkgs; }).termuxPackages;
in
{
  imports = [
    ../../modules/dotfiles.nix
    ../../home-manager/cli/bat.nix
    ../../home-manager/cli/eget.nix
    ../../home-manager/cli/eza.nix
    ../../home-manager/cli/fd.nix
    ../../home-manager/cli/nvim/termux.nix
    ../../home-manager/cli/ripgrep.nix
    ../../home-manager/cli/tmux
    ../../home-manager/cli/zsh/atuin.nix
    ../../home-manager/cli/zsh/completions
    ../../home-manager/cli/zsh/config/source-me.nix
    ../../home-manager/cli/zsh/direnv.nix
    ../../home-manager/cli/zsh/fzf.nix
    ../../home-manager/cli/zsh/tools/fd.nix
    ../../home-manager/cli/zsh/tools/jq.nix
    ../../home-manager/cli/zsh/tools/adb.nix
    ../../home-manager/cli/zsh/tools/ketall.nix
    ../../home-manager/cli/zsh/tools/krew.nix
    ../../home-manager/cli/zsh/tools/kubectl-ksh.nix
    ../../home-manager/cli/zsh/tools/kubectl-socks5-proxy.nix
    ../../home-manager/cli/zsh/tools/kubectl-watch.nix
    ../../home-manager/cli/zsh/tools/nbx.nix
    ../../home-manager/cli/zsh/tools/netbird.nix
    ../../home-manager/cli/zsh/tools/tables.nix
    ../../home-manager/cli/zsh/tools/yank.nix
    ../../home-manager/cli/zsh/tools/xcp.nix
    ../../home-manager/cli/zsh/tools/termux/assh.nix
    ../../home-manager/cli/zsh/tools/termux/home-assistant-cli.nix
    ../../home-manager/cli/zsh/tools/termux/jc.nix
    ../../home-manager/cli/zsh/tools/termux/kubectl.nix
    ../../home-manager/cli/zsh/tools/termux/ldifj.nix
    ../../home-manager/cli/zsh/tools/termux/linkding-cli.nix
    ../../home-manager/cli/zsh/tools/termux/mani.nix
    ../../home-manager/cli/zsh/tools/termux/myl.nix
    ../../home-manager/cli/zsh/tools/termux/rancher.nix
    ../../home-manager/cli/zsh/tools/termux/rbw.nix
    ../../home-manager/cli/zsh/tools/termux/slack-react.nix
    ../../home-manager/cli/zsh/tools/termux/termux-tools.nix
    ../../home-manager/cli/zsh/tools/termux/tmux-slay.nix
    ../../home-manager/cli/zsh/tools/termux/tmux-xpanes.nix
    ../../home-manager/cli/zsh/tools/termux/udocker.nix
    ../../home-manager/cli/zsh/vivid.nix
    ../../home-manager/cli/zsh/zoxide.nix
    ./termux-zsh-runtime.nix
    ../../home-manager/cli/zsh/config/base.nix
    ../../home-manager/cli/zsh/config/completions.nix
    ../../home-manager/cli/zsh/config/hashicorp-completions.nix
    ../../home-manager/cli/zsh/config/hm.nix
    ../../home-manager/cli/zsh/config/portable.nix
    ../../home-manager/cli/zsh/plugins
    ../../home-manager/cli/zsh/termux-shell.nix
    ../../home-manager/termux-options.nix
    ../domains.nix
  ];

  options.termux = {
    homeFiles = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        ".config/zsh/.zprofile"
        ".config/zsh/.zshenv"
        ".config/zsh/.zshrc"
        ".config/zsh/zhj.zsh"
        ".config/zsh/termux/atuin-init.zsh"
        ".config/zsh/termux/direnv-init.zsh"
        ".config/zsh/termux/fzf-init.zsh"
        ".config/zsh/termux/zoxide-init.zsh"
        ".config/zsh/termux/vivid.zsh"
        ".config/zsh/termux/prompt-color.zsh"
        ".config/nixpp/config.toml"
        ".config/termux/tasker/tudo"
        ".config/zsh/custom/os/home-manager/system.zsh"
        ".config/atuin/config.toml"
        ".config/zsh/completions/_tmux-slay"
        ".config/tmux/bin/xpanes"
        ".config/zsh/completions/_xpanes"
        ".local/share/man/man1/xpanes.1"
        ".config/zsh/completions/_ipmi"
        ".config/zsh/completions/_hass-cli"
        ".config/zsh/completions/_jc"
        ".config/zsh/completions/_kubectl"
        ".config/zsh/completions/_linkding"
        ".config/zsh/completions/_mani"
        ".config/zsh/completions/_ossh"
        ".config/zsh/completions/_rbw"
        ".config/zsh/completions/_revolver"
        ".config/zsh/completions/_whatsmy"
        ".config/zsh/completions/_zunit"
        ".config/zsh/completions/_extract"
        ".config/zsh/completions/source-me.zsh"
        ".config/jq/colors"
        ".config/jq/plib"
        ".local/share/man/man1/mani.1"
        ".config/tmux/tmux.conf"
        ".config/nvim/init.lua"
        ".config/nvim/after"
        ".config/nvim/lua"
        ".config/nvim/snippets"
        ".config/nvim/stylua.toml"
      ]
      ++ lib.optionals (config.termux.ssh.hostKeysSopsFile != null) [
        ".local/share/termux-native/ssh-host-keys.sops.yaml"
      ]
      ++ lib.optionals (config.termux.ssh.knownHostsSopsFile != null) [
        ".local/share/termux-native/ssh-known-hosts.sops.yaml"
      ]
      ++ lib.optionals (config.termux.gpg.sopsFile != null) [
        ".local/share/termux-native/gpg.sops.yaml"
      ];
      description = ''
        Relative Home Manager output files copied into a Termux generation.
        This allowlist keeps unrelated home and private dotfiles out of bundles.
      '';
    };

    ssh.hostKeysSopsFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Encrypted per-host OpenSSH host keys included in the Termux generation.";
    };

    ssh.knownHostsSopsFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Encrypted OpenSSH known-hosts entries materialized on the Termux host.";
    };

    gpg.sopsFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = inputs.nixos-config-private.outPath + "/secrets/nixos-gpg.sops.yaml";
      description = "Encrypted GPG secret-key data imported into the Termux user's GnuPG home.";
    };

  };

  # Disable Linux packages for programs supplied by the Termux prefix. Packages
  # explicitly added through home.packages must target Android/Bionic.
  config = lib.mkMerge [
    {
      termux = {
        enable = true;
        packages = [
          "bash"
          "ca-certificates"
          "coreutils"
          "gnupg"
          "curl"
          "diff-so-fancy"
          "git"
          "grep"
          "jq"
          "yadm"
          "libngtcp2"
          "less"
          "openssh"
          "atuin"
          "bat"
          "eza"
          "fd"
          "gzip"
          "tmux"
          "ripgrep"
          "unzip"
          "vivid"
          "zip"
          "udocker"
          "procps"
          "python"
          "shellcheck"
          "sed"
          "tar"
          "tudo"
          "util-linux"
          "zsh"
        ];
      };

      xdg = {
        enable = true;
        configFile = {
          "nixpp/config.toml".text = ''
            [defaults]
            substituter = "s3://nix-cache-brkn-lol?endpoint=s3.openstack.de-west-01.wiit-cloud.io&region=default&scheme=https&profile=niks3&priority=30"
            flake = "github:pschmitt/nixos-config#termux-native-${hostname}-bundle"
            builders = [ "rofl-13", "rofl-14", "rofl-15", "rofl-16" ]
            public_keys = [
              "rofl-10:vYRBSypcO/0NnPsDxgSELIcJotU/LmZ1f6vZUKUmty0=",
              "rofl-13:ESRCqy2jcftg690k98KSNqF6LgOqz1X7ZnXXE//WWD0=",
              "rofl-14:XkEHSleW71wOnEnAcTZnYi/badnlAJAUxt6SIzbYsG8=",
              "rofl-15:x68gyyrKadDfvJKdpPkRvmPckrYF6XqzlKaqs2xheVw=",
              "rofl-16:DB8WQ415B8v3P9r1R8U4pO1iKrOAldbBHbSz+chryXI=",
              "gh-actions:x+pfxw4yRpZbonnjaCR0nIm5eN1wOGAki0soDQyFjJQ=",
            ]
            aws_credentials_command = [
              "rbw",
              "get",
              "--raw",
              "--exact",
              "nixpp Niks3 cache"
            ]
          '';
          "termux/tasker/tudo" = {
            executable = true;
            text = ''
              #!/data/data/com.termux/files/usr/bin/sh
              exec "$PREFIX/bin/tudo" "$@"
            '';
          };
          "zsh/termux/prompt-color.zsh".text = ''
            if [[ -z "''${host_color:-}" ]]
            then
              typeset -g host_color=${lib.escapeShellArg config.dotfiles.promptColor}
            fi
          '';
          "zsh/zhj.zsh".text = builtins.readFile ../../pkgs/local/zhj/zhj.zsh;
          "zsh/completions/_rbw".source = "${pkgsTermux.rbw}/share/zsh/site-functions/_rbw";
          "zsh/completions/_extract".source = "${pkgs.oh-my-zsh}/share/oh-my-zsh/plugins/extract/_extract";
          "zsh/custom/os/home-manager/system.zsh".text = ''
            functions[nvim]=${lib.escapeShellArg ''XDG_CONFIG_HOME="$TERMUX_GENERATION/home/.config" command nvim "$@"''}
          '';
        };
        dataFile = {
          "termux-native/ssh-host-keys.sops.yaml" = lib.mkIf (config.termux.ssh.hostKeysSopsFile != null) {
            source = config.termux.ssh.hostKeysSopsFile;
          };
          "termux-native/ssh-known-hosts.sops.yaml" =
            lib.mkIf (config.termux.ssh.knownHostsSopsFile != null)
              {
                source = config.termux.ssh.knownHostsSopsFile;
              };
          "termux-native/gpg.sops.yaml" = lib.mkIf (config.termux.gpg.sopsFile != null) {
            source = config.termux.gpg.sopsFile;
          };
        };
      };

      home = {
        username = "termux";
        homeDirectory = "/data/data/com.termux/files/home";
        stateVersion = "26.05";
        sessionVariables = {
          HOST = hostname;
          HOSTNAME = hostname;
          GNUPGHOME = "${config.xdg.configHome}/gnupg";
        };
      };

      home.packages = [
        pkgsTermux.hwatch
        pkgsTermux.nixpp
        pkgsTermux.obs-cli
        pkgsTermux.rbw
        pkgsTermux.sops
        pkgsTermux.ssh-to-age
        pkgsTermux.emoji-fzf
        pkgsTermux.zhj
      ];

      programs.zsh = {
        enable = lib.mkForce true;
        enableCompletion = false;
        dotDir = lib.mkForce "${config.xdg.configHome}/zsh";
        sessionVariables.TERMUX_NATIVE_ENABLED = "1";
        shellAliases = {
          tmux = lib.mkForce ''command tmux -f "$TERMUX_GENERATION/home/.config/tmux/tmux.conf"'';
        };
        initContent = lib.mkAfter ''
          ${builtins.readFile ../../android/termux-native/shell.zsh}

            if [[ -o interactive && -n "''${_comps+x}" ]]
            then
              autoload -Uz _rbw
              compdef _rbw rbw
            fi
        '';
      };

    }
    (lib.mkIf (config.termux.enable && config.programs.zsh.enable) {
      programs.zsh.package = null;
    })
  ];
}
