# This is your system's configuration file.
# Use this to configure your system environment (it replaces /etc/nixos/configuration.nix)

{ inputs, outputs, lib, config, pkgs, ... }: {

  nixpkgs = {
    # You can add overlays here
    overlays = [
      # Add overlays your own flake exports (from overlays and pkgs dir):
      outputs.overlays.additions
      outputs.overlays.modifications
      outputs.overlays.unstable-packages

      # You can also add overlays exported from other flakes:
      # neovim-nightly-overlay.overlays.default

      # Or define it inline, for example:
      # (final: prev: {
      #   hi = final.hello.overrideAttrs (oldAttrs: {
      #     patches = [ ./change-hello-to-hi.patch ];
      #   });
      # })
    ];
    # Configure your nixpkgs instance
    config = {
      # Disable if you don't want unfree packages
      allowUnfree = true;
    };
  };

  nix = {
    # This will add each flake input as a registry
    # To make nix3 commands consistent with your flake
    registry = lib.mapAttrs (_: value: { flake = value; }) inputs;

    # This will additionally add your inputs to the system's legacy channels
    # Making legacy nix commands consistent as well, awesome!
    nixPath = lib.mapAttrsToList (key: value: "${key}=${value.to.path}") config.nix.registry;

    settings = {
      # Enable flakes and new 'nix' command
      experimental-features = "nix-command flakes";
      # Deduplicate and optimize nix store
      auto-optimise-store = true;
    };
  };

  boot = {
    # Enable all MagicSysRq keys
    kernel.sysctl = { "kernel.sysrq" = 1; };
    kernelPackages = pkgs.linuxPackages_latest;
  };

  # Define a user account. Don't forget to set a password with ‘passwd’.
  users.users.pschmitt = {
    isNormalUser = true;
    description = "Philipp Schmitt";
    extraGroups = [
      "adbusers"
      "docker"
      "mlocate"
      "networkmanager"
      "pschmitt"
      "video"
      "wheel"
    ];
    packages = with pkgs; [ ];
    openssh.authorizedKeys.keys =
      let authorizedKeys = builtins.fetchurl {
        url = "https://github.com/pschmitt.keys";
        sha256 = "0s2ix9lmhv5vc6av3jymhkkm41dbq7acbjqryb5l1lsmax159fh8";
      };
      in pkgs.lib.splitString "\n" (builtins.readFile authorizedKeys);
    shell = pkgs.zsh;
  };


  # This setups a SSH server. Very important if you're setting up a headless system.
  # Feel free to remove if you don't need it.
  services.openssh = {
    enable = true;
    # Forbid root login through SSH.
    # permitRootLogin = "no";
    # Use keys only. Remove if you want to SSH using password (not recommended)
    # passwordAuthentication = false;
  };

  virtualisation.docker = {
    enable = true;
    storageDriver = "btrfs";
    package = pkgs.unstable.docker_24;
  };

  programs.nix-ld = {
    enable = true;
    # libraries = [];
  };

  # started in user sessions.
  # programs.mtr.enable = true;
  programs.gnupg.agent = {
    enable = true;
    pinentryFlavor = "gnome3";
    enableSSHSupport = true;
  };

  programs.tmux = {
    enable = true;
    clock24 = true;
    newSession = true;
    terminal = "tmux-direct";
    aggressiveResize = true;
    # Set prefix to C-a
    shortcut = "a";
    keyMode = "vi";
    # extraConfig = ''
    #   set-option -g mouse on
    #   '';
    plugins = with pkgs; [
      tmuxPlugins.sensible
      tmuxPlugins.pain-control
      tmuxPlugins.onedark-theme
      tmuxPlugins.mode-indicator
      tmuxPlugins.fuzzback # prefix-?
    ];
  };

  programs.npm = {
    enable = true;
    package = pkgs.nodePackages_latest.npm;
    # FIXME This does not seem to be enough to override the dirs npm uses
    # We might need to write this to /usr/etc/npmrc as the Arch Wiki suggests:
    # https://wiki.archlinux.org/title/XDG_Base_Directory
    npmrc = ''
      prefix=''${XDG_DATA_HOME}/npm
      cache=''${XDG_CACHE_HOME}/npm
      init-module=''${XDG_CONFIG_HOME}/npm/config/npm-init.js'
    '';
  };

  # Make ZSH respect XDG
  environment.etc = {
    "zshenv.local" = {
      text = ''
        export ZDOTDIR="$HOME/.config/zsh"
      '';
      mode = "0644";
    };
  };

  hardware.enableAllFirmware = true;

  # https://nixos.wiki/wiki/FAQ/When_do_I_update_stateVersion
  system = {
    stateVersion = "23.05";
    # autoUpgrade = {
    #   enable = true;
    #   channel = "https://nixos.org/channels/nixos-23.05";
    # };
  };
}
