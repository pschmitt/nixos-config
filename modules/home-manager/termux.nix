{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  termuxBat = pkgs.callPackage ../../pkgs/termux-native/bat.nix {
    llvm = pkgs.llvmPackages.llvm;
    package = pkgs.bat;
  };
  termuxEza = pkgs.callPackage ../../pkgs/termux-native/eza.nix {
    llvm = pkgs.llvmPackages.llvm;
    package = pkgs.eza;
  };
  termuxFd = pkgs.callPackage ../../pkgs/termux-native/fd.nix {
    llvm = pkgs.llvmPackages.llvm;
    package = pkgs.fd;
  };
  termuxZip = pkgs.callPackage ../../pkgs/termux-native/zip.nix {
    llvm = pkgs.llvmPackages.llvm;
    package = pkgs.pkgsCross.aarch64-android-prebuilt.zip;
  };
  termuxUnzip = pkgs.callPackage ../../pkgs/termux-native/unzip.nix {
    bzip2 = pkgs.pkgsCross.aarch64-android-prebuilt.bzip2;
    llvm = pkgs.llvmPackages.llvm;
    package = pkgs.pkgsCross.aarch64-android-prebuilt.unzip;
  };
  termuxRipgrep = pkgs.callPackage ../../pkgs/termux-native/ripgrep.nix {
    llvm = pkgs.llvmPackages.llvm;
    package = pkgs.ripgrep;
    crossPackage = pkgs.pkgsCross.aarch64-android-prebuilt.ripgrep.override {
      withPCRE2 = false;
    };
  };
  termuxGzip = pkgs.callPackage ../../pkgs/termux-native/gzip.nix {
    llvm = pkgs.llvmPackages.llvm;
    package = pkgs.pkgsCross.aarch64-android-prebuilt.gzip;
  };
  termuxAtuin = pkgs.callPackage ../../pkgs/termux-native/atuin.nix { };
  termuxVivid = pkgs.callPackage ../../pkgs/termux-native/vivid.nix {
    llvm = pkgs.llvmPackages.llvm;
    package = pkgs.vivid;
  };
  termuxSshToAge = pkgs.callPackage ../../pkgs/termux-native/ssh-to-age.nix { };
in
{
  imports = [
    ../../home-manager/cli/nvim/termux.nix
    ../../home-manager/cli/tmux
    ./termux-zsh-runtime.nix
    ../../home-manager/cli/zsh/config/base.nix
    ../../home-manager/cli/zsh/config/portable.nix
    ../../home-manager/cli/zsh/termux-shell.nix
    ../domains.nix
  ];

  options.termux = {
    enable = lib.mkEnableOption "Termux-specific Home Manager configuration";

    packages = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Termux APT packages required by the Home Manager profile.";
    };

    homeFiles = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        ".config/zsh/.zprofile"
        ".config/zsh/.zshenv"
        ".config/zsh/.zshrc"
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
        (pkgs.callPackage ../../pkgs/nixpp-termux { inherit inputs; })
        termuxBat
        termuxEza
        termuxFd
        termuxRipgrep
        termuxVivid
        termuxZip
        termuxUnzip
        termuxGzip
        termuxAtuin
        termuxSshToAge
      ];

      termux.packages = [
        "bash"
        "coreutils"
        "curl"
        "direnv"
        "git"
        "grep"
        "jq"
        "libngtcp2"
        "less"
        "openssh"
        "procps"
        "sed"
        "tar"
        "util-linux"
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
