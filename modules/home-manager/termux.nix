{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  fromNixpkgs =
    {
      package,
      crossPackage ? null,
      skipPostInstall ? false,
      skipPostFixup ? false,
    }:
    pkgs.callPackage ../../pkgs/termux-native/from-nixpkgs.nix {
      inherit
        package
        crossPackage
        skipPostInstall
        skipPostFixup
        ;
    };
  termuxBat = fromNixpkgs {
    package = pkgs.bat;
    # Nix wraps bat with a store-specific less path; Termux supplies less on PATH.
    skipPostFixup = true;
  };
  termuxEza = fromNixpkgs {
    package = pkgs.eza;
    # The export contract ships eza's executable, not its Pandoc-built docs.
    skipPostInstall = true;
    crossPackage = pkgs.pkgsCross.aarch64-android-prebuilt.eza.overrideAttrs (old: {
      outputs = [ "out" ];
      meta = (old.meta or { }) // {
        outputsToInstall = [ "out" ];
      };
      nativeBuildInputs = builtins.filter (input: lib.getName input != "pandoc-cli") (
        old.nativeBuildInputs or [ ]
      );
    });
  };
  termuxFd = fromNixpkgs { package = pkgs.fd; };
  termuxZip = pkgs.callPackage ../../pkgs/termux-native/zip.nix {
    package = pkgs.pkgsCross.aarch64-android-prebuilt.zip;
  };
  termuxUnzip = pkgs.callPackage ../../pkgs/termux-native/unzip.nix {
    bzip2 = pkgs.pkgsCross.aarch64-android-prebuilt.bzip2;
    package = pkgs.pkgsCross.aarch64-android-prebuilt.unzip;
  };
  termuxRipgrep = fromNixpkgs {
    package = pkgs.ripgrep;
    # The upstream hook executes the Android binary under QEMU to generate
    # docs/completions; QEMU has no Android system linker on the build host.
    skipPostFixup = true;
    crossPackage = pkgs.pkgsCross.aarch64-android-prebuilt.ripgrep.override {
      withPCRE2 = true;
    };
  };
  termuxGzip = pkgs.callPackage ../../pkgs/termux-native/gzip.nix {
    package = pkgs.pkgsCross.aarch64-android-prebuilt.gzip;
  };
  termuxVivid = fromNixpkgs { package = pkgs.vivid; };
  termuxSshToAge = pkgs.callPackage ../../pkgs/termux-native/ssh-to-age.nix { };
  termuxEmojiFzf = pkgs.callPackage ../../pkgs/termux-native/python-application.nix {
    package = pkgs.emoji-fzf;
    python = pkgs.python3;
  };
  goNative =
    {
      package,
      binary,
      buildBinary ? binary,
      skipPostInstall ? false,
    }:
    pkgs.callPackage ../../pkgs/termux-native/go-binary.nix {
      inherit
        package
        binary
        buildBinary
        skipPostInstall
        ;
    };
  termuxAssh = goNative {
    package = pkgs.assh;
    binary = "assh";
    skipPostInstall = true;
  };
  termuxRancher = goNative {
    package = pkgs.rancher;
    binary = "rancher";
    buildBinary = "cli";
    skipPostInstall = true;
  };
in
{
  imports = [
    ../../home-manager/cli/nvim/termux.nix
    ../../home-manager/cli/tmux
    ../../home-manager/cli/zsh/atuin.nix
    ../../home-manager/cli/zsh/tools/termux/mani.nix
    ../../home-manager/cli/zsh/tools/termux/termux-tools.nix
    ./termux-zsh-runtime.nix
    ../../home-manager/cli/zsh/config/base.nix
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
        ".config/zsh/custom/os/home-manager/system.zsh"
        ".config/atuin/config.toml"
        ".config/zsh/completions/_mani"
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
        (pkgs.callPackage ../../pkgs/nixpp-termux { inherit inputs; })
        termuxBat
        termuxEza
        termuxFd
        termuxRipgrep
        termuxVivid
        termuxZip
        termuxUnzip
        termuxGzip
        termuxSshToAge
        termuxEmojiFzf
        termuxAssh
        termuxRancher
      ];

      termux.packages = [
        "bash"
        "coreutils"
        "curl"
        "direnv"
        "diff-so-fancy"
        "fzf"
        "git"
        "grep"
        "jq"
        "libngtcp2"
        "less"
        "openssh"
        "procps"
        "python"
        "shellcheck"
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
