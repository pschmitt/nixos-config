{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
{
  imports = [
    ../../home-manager/cli
    ../domains.nix
  ];

  options.termux.homeFiles = lib.mkOption {
    type = lib.types.listOf lib.types.str;
    default = [
      ".config/zsh/.zprofile"
      ".config/zsh/.zshenv"
      ".config/zsh/.zshrc"
      ".config/zsh/completions/source-me.zsh"
      ".config/zsh/custom/os/home-manager/system.zsh"
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
        file.".config/zsh/.zshenv".text = lib.mkForce (
          builtins.readFile ../../android/termux-native/shell-env.zsh
        );
      };

      home.packages = [
        (pkgs.callPackage ../../pkgs/nixpp-termux { inherit inputs; })
        (pkgs.callPackage ../../pkgs/termux-native/go-binary.nix {
          inherit pkgs;
          package = pkgs.ssh-to-age;
          binary = "ssh-to-age";
        })
      ];

      termux.packages = [
        "bash"
        "bat"
        "coreutils"
        "curl"
        "direnv"
        "eza"
        "fd"
        "fzf"
        "git"
        "grep"
        "gzip"
        "jq"
        "libngtcp2"
        "openssh"
        "procps"
        "ripgrep"
        "sed"
        "tar"
        "util-linux"
        "unzip"
        "vivid"
        "zip"
        "zoxide"
        "zsh"
      ];

      programs.zsh = {
        enable = lib.mkForce true;
        enableCompletion = false;
        dotDir = lib.mkForce "${config.xdg.configHome}/zsh";
        initContent = builtins.readFile ../../android/termux-native/shell.zsh;
      };

      xdg.configFile = {
        "zsh/custom/os/home-manager/system.zsh".text = lib.mkAfter ''
          # These generated configs live in the active profile generation. Keep
          # the user's real $HOME/.config tree, including yadm-managed files, intact.
          function nvim() {
            XDG_CONFIG_HOME="$TERMUX_GENERATION/home/.config" command nvim "$@"
          }

          function tmux() {
            command tmux -f "$TERMUX_GENERATION/home/.config/tmux/tmux.conf" "$@"
          }
        '';
      };
    }
    (lib.mkIf (config.termux.enable && config.programs.zsh.enable) {
      programs.zsh.package = null;
    })
  ];
}
