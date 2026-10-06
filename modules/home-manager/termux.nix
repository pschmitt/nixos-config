{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  pkgsTermux =
    (import ../../pkgs/termux-native/package-set.nix { inherit inputs pkgs; }).termuxPackages;
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
    ../../home-manager/cli/zsh/tools/termux/assh.nix
    ../../home-manager/cli/zsh/tools/termux/jc.nix
    ../../home-manager/cli/zsh/tools/termux/kubectl.nix
    ../../home-manager/cli/zsh/tools/termux/mani.nix
    ../../home-manager/cli/zsh/tools/termux/rancher.nix
    ../../home-manager/cli/zsh/tools/termux/rbw.nix
    ../../home-manager/cli/zsh/tools/termux/slack-react.nix
    ../../home-manager/cli/zsh/tools/termux/termux-tools.nix
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
        ".config/zsh/termux/atuin-init.zsh"
        ".config/zsh/termux/direnv-init.zsh"
        ".config/zsh/termux/fzf-init.zsh"
        ".config/zsh/termux/zoxide-init.zsh"
        ".config/zsh/termux/vivid.zsh"
        ".config/zsh/termux/prompt-color.zsh"
        ".config/atuin/config.toml"
        ".config/zsh/completions/_ipmi"
        ".config/zsh/completions/_jc"
        ".config/zsh/completions/_kubectl"
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
      ];
      description = ''
        Relative Home Manager output files copied into a Termux generation.
        This allowlist keeps unrelated home and private dotfiles out of bundles.
      '';
    };
  };

  # Disable Linux packages for programs supplied by the Termux prefix. Packages
  # explicitly added through home.packages must target Android/Bionic.
  config = lib.mkMerge [
    {
      xdg.enable = true;
      termux.enable = true;

      home = {
        username = "termux";
        homeDirectory = "/data/data/com.termux/files/home";
        stateVersion = "26.05";
      };

      home.packages = [
        pkgsTermux.nixpp
        pkgsTermux.obs-cli
        pkgsTermux.rbw
        pkgsTermux.ssh-to-age
        pkgsTermux.emoji-fzf
      ];

      termux.packages = [
        "bash"
        "ca-certificates"
        "coreutils"
        "curl"
        "diff-so-fancy"
        "git"
        "grep"
        "jq"
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
        "util-linux"
        "zsh"
      ];

      programs.zsh = {
        enable = lib.mkForce true;
        enableCompletion = false;
        dotDir = lib.mkForce "${config.xdg.configHome}/zsh";
        shellAliases = {
          nvim = lib.mkForce ''XDG_CONFIG_HOME="$TERMUX_GENERATION/home/.config" command nvim'';
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

      xdg.configFile = {
        "zsh/termux/prompt-color.zsh".text = ''
          typeset -g host_color=${lib.escapeShellArg config.dotfiles.promptColor}
        '';
        "zsh/completions/_rbw".source = "${pkgsTermux.rbw}/share/zsh/site-functions/_rbw";
        "zsh/completions/_extract".source = "${pkgs.oh-my-zsh}/share/oh-my-zsh/plugins/extract/_extract";
      };
    }
    (lib.mkIf (config.termux.enable && config.programs.zsh.enable) {
      programs.zsh.package = null;
    })
  ];
}
