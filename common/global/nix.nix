{
  config,
  inputs,
  lib,
  outputs,
  pkgs,
  ...
}:
{
  sops = {
    secrets = {
      "ssh/nix-remote-builder/privkey" = { };
      "nix/github_token" = { };
    };
    templates.nix-access-token-github.content = ''
      access-tokens = github.com=${config.sops.placeholder."nix/github_token"}
    '';
  };

  boot.binfmt.emulatedSystems = if pkgs.system != "aarch64-linux" then [ "aarch64-linux" ] else [ ];

  nix = {
    # GitHub access token
    extraOptions = ''
      !include ${config.sops.templates.nix-access-token-github.path}
    '';

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

      trusted-users = [
        "root"
        "@wheel"
      ];

      substituters =
        [
          # NOTE cache.nixos.org is enabled by default, adding it here only
          # duplicates it
          # "https://cache.nixos.org"
          "https://hyprland.cachix.org"
          "https://nix-community.cachix.org"
          "https://pschmitt-nixos-config.cachix.org"
          "https://cache.garnix.io"
          # "ssh://nix-remote-builder@rofl-02.heimat.dev?ssh-key=${
          #   config.sops.secrets."ssh/nix-remote-builder/privkey".path
          # }"
          # "ssh://nix-remote-builder@rofl-03.heimat.dev?ssh-key=${
          #   config.sops.secrets."ssh/nix-remote-builder/privkey".path
          # }"
          # "https://nix-cache.heimat.dev"
        ]
        # don't use local http cache on the same host
        ++ lib.optionals (config.networking.hostName != "rofl-02") [ "https://cache.rofl-02.nb.brkn.lol" ];
        # FIXME rofl-03 has some issues with netbird
        # ++ lib.optionals (config.networking.hostName != "rofl-03") [ "https://cache.rofl-03.nb.brkn.lol" ];

      # attic auth (nix.rofl-01.heimat.dev)
      # netrc-file = "/etc/nix/netrc";

      trusted-public-keys = [
        # NOTE cache.nixos.org is enabled by default, adding it here only
        # duplicates it
        # "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
        "hyprland.cachix.org-1:a7pgxzMz7+chwVL3/pzj6jIBMioiJM7ypFP8PwtkuGc="
        "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
        "pschmitt-nixos-config.cachix.org-1:cE7rK+O+QCIEewMOOk3C7JYOhSXxqgLzNpm+tdSMkMk="
        "cache.garnix.io:CTFPyKSLcx5RMJKfLo5EEPUObbA78b0YQ2DTCJXqr9g="
        # "nix-cache.heimat.dev:k/zdgSv+6lcJ/9DRILjA7H18eIlFSA0OwzyqqXEwySM="
        "rofl-02:OjuEw7+xiIgDDHLLoRHY6h4CQpl0Ie96qyjeJyQRJ38="
        "rofl-03:p25y1GufWGd6aWpimb8j6F0obxn3jwYCj7sCCXgp7A0="
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

      permittedInsecurePackages = [ "freeimage-unstable-2021-11-01" ];
    };
  };

  programs.nix-ld = {
    enable = true;
    # libraries = [];
  };

  # Do not use /tmp (50% RAM tmpfs) for builds
  systemd.services.nix-daemon.environment.TMPDIR = "/nix/tmp";
  # Create /nix/tmp and clean it up every 48 hours (2 days)
  systemd.tmpfiles.rules = [ "d /nix/tmp 0755 root root 2d" ];

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
    stateVersion = "24.05";
    # autoUpgrade = {
    #   enable = true;
    #   channel = "https://nixos.org/channels/nixos-23.05";
    # };
  };
}
