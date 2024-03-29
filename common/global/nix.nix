{ config, inputs, lib, outputs, pkgs, ... }:
{
  imports = [
    ./nix-remote-build.nix
  ];

  age = {
    secrets = {
      nix-netrc = {
        file = ../../secrets/${config.networking.hostName}/nix-netrc.age;
        owner = "root";
        # FIXME is nixbld the right group?
        group = "nixbld";
        mode = "0440";
      };
    };
  };

  environment.etc."nix/netrc" = {
    user = "root";
    source = config.age.secrets.nix-netrc.path;
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

      trusted-users = [ "root" "@wheel" ];

      substituters = [
        # NOTE cache.nixos.org is enabled by default, adding it here only
        # duplicates it
        # "https://cache.nixos.org"
        "https://hyprland.cachix.org"
        "https://nix-community.cachix.org"
        "https://pschmitt-nixos-config.cachix.org"
        "https://cache.garnix.io"
        "https://nix-cache.heimat.dev"
      ];

      # attic auth (nix.rofl-01.heimat.dev)
      netrc-file = "/etc/nix/netrc";

      trusted-public-keys = [
        # NOTE cache.nixos.org is enabled by default, adding it here only
        # duplicates it
        # "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
        "hyprland.cachix.org-1:a7pgxzMz7+chwVL3/pzj6jIBMioiJM7ypFP8PwtkuGc="
        "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
        "pschmitt-nixos-config.cachix.org-1:cE7rK+O+QCIEewMOOk3C7JYOhSXxqgLzNpm+tdSMkMk="
        "cache.garnix.io:CTFPyKSLcx5RMJKfLo5EEPUObbA78b0YQ2DTCJXqr9g="
        "nix-cache.heimat.dev:k/zdgSv+6lcJ/9DRILjA7H18eIlFSA0OwzyqqXEwySM="
      ];
    };

    # Do not attempt to murder the laptop when running nixos rebuild
    daemonCPUSchedPolicy = "idle";
    daemonIOSchedClass = "idle";
  };

  nixpkgs = {
    # You can add overlays here
    overlays = [
      # Add overlays your own flake exports (from overlays and pkgs dir):
      outputs.overlays.additions
      outputs.overlays.modifications
      outputs.overlays.unstable-packages
      outputs.overlays.old-packages

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

      permittedInsecurePackages = [
        "freeimage-unstable-2021-11-01"
      ];
    };
  };

  programs.nix-ld = {
    enable = true;
    # libraries = [];
  };

  # Do not use /tmp (50% RAM tmpfs) for builds
  systemd.services.nix-daemon.environment.TMPDIR = "/nix/tmp";
  # Create /nix/tmp and clean it up every 48 hours (2 days)
  systemd.tmpfiles.rules = [
    "d /nix/tmp 0755 root root 2d"
  ];

  programs.command-not-found.enable = false;

  environment.systemPackages = with pkgs; [
    # nix
    inputs.agenix.packages.${system}.default
    # FIXME attic fails to build as of 2024-01-16
    inputs.attic.packages.${system}.default
    nix-prefetch
  ];

  # https://nixos.wiki/wiki/FAQ/When_do_I_update_stateVersion
  system = {
    stateVersion = "23.11";
    # autoUpgrade = {
    #   enable = true;
    #   channel = "https://nixos.org/channels/nixos-23.05";
    # };
  };
}
