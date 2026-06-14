{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
{
  imports = [
    inputs.nix-index-database.nixosModules.nix-index
    ./nix/secrets.nix
    ./nix/overlays.nix
  ];

  boot.binfmt.emulatedSystems =
    if pkgs.stdenv.hostPlatform.system != "aarch64-linux" then
      [
        "aarch64-linux"
        "i686-linux"
      ]
    else
      [ ];

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

    gc = {
      automatic = true;
      dates = lib.mkDefault "weekly";
      persistent = true;
      options = "--delete-older-than 10d";
    };

    settings = {
      # Enable flakes and new 'nix' command
      experimental-features = "nix-command flakes";
      # Deduplicate and optimize nix store
      auto-optimise-store = true;

      trusted-users = [
        "root"
        "@wheel"
      ];

      substituters = [
        # NOTE cache.nixos.org is enabled by default, adding it here only
        # duplicates it
        # "https://cache.nixos.org"
        "https://hyprland.cachix.org"
        "https://nix-community.cachix.org"
        "https://pschmitt-nixos-config.cachix.org"
        "https://cache.numtide.com"

        # FIXME cache.garnix.io uses a wrong cert as of 2025-01-12
        #
        # » openssl::cat --pretty cache.garnix.io
        # CN         SAN  ISSUER         STATUS  EXPIRES
        # garnix.io  N/A  Let's Encrypt  valid   2025-02-13T17:45:36Z
        #
        # Might be due to a maintenance window:
        # https://discord.com/channels/960235377506025542/960235378030301216/1327366389769572483
        # "https://cache.garnix.io"

        # "https://nix-cache.brkn.lol"
      ]
      # don't use local http cache on the same host
      ++ lib.optionals (config.networking.hostName != "rofl-10") [ "https://cache.rofl-10.brkn.lol" ]
      ++ lib.optionals (config.networking.hostName != "rofl-13") [ "https://cache.rofl-13.brkn.lol" ]
      ++ lib.optionals (config.networking.hostName != "rofl-14") [ "https://cache.rofl-14.brkn.lol" ];

      # private caches
      netrc-file = config.sops.templates.nix-cache-netrc.path;

      trusted-public-keys = [
        # NOTE cache.nixos.org is enabled by default, adding it here only
        # duplicates it
        # "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
        "hyprland.cachix.org-1:a7pgxzMz7+chwVL3/pzj6jIBMioiJM7ypFP8PwtkuGc="
        "niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g="
        "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
        "pschmitt-nixos-config.cachix.org-1:cE7rK+O+QCIEewMOOk3C7JYOhSXxqgLzNpm+tdSMkMk="
        "cache.garnix.io:CTFPyKSLcx5RMJKfLo5EEPUObbA78b0YQ2DTCJXqr9g="
        # "nix-cache.brkn.lol:k/zdgSv+6lcJ/9DRILjA7H18eIlFSA0OwzyqqXEwySM="
        "rofl-10:vYRBSypcO/0NnPsDxgSELIcJotU/LmZ1f6vZUKUmty0="
        "rofl-13:ESRCqy2jcftg690k98KSNqF6LgOqz1X7ZnXXE//WWD0="
        "rofl-14:XkEHSleW71wOnEnAcTZnYi/badnlAJAUxt6SIzbYsG8="

        # cache key we use in github actions for CI builds
        "gh-actions:x+pfxw4yRpZbonnjaCR0nIm5eN1wOGAki0soDQyFjJQ="
      ];
    };

    # Do not attempt to murder the laptop when running nixos rebuild
    daemonCPUSchedPolicy = "idle";
    daemonIOSchedClass = "idle";
  };

  programs = {
    nh = {
      enable = true;
      flake = "/etc/nixos";
    };

    nix-ld = {
      enable = true;
      # libraries = [];
    };

    command-not-found.enable = false;
  };

  # Do not use /tmp (50% RAM tmpfs) for builds
  systemd.services.nix-daemon.environment.TMPDIR = "/nix/tmp";
  # Create /nix/tmp and clean it up every 48 hours (2 days)
  systemd.tmpfiles.rules = [ "d /nix/tmp 0755 root root 2d" ];

  environment.systemPackages = with pkgs; [
    # inputs.attic.packages.${system}.default
    inputs.nixos-needsreboot.packages.${pkgs.stdenv.hostPlatform.system}.default
    nix-prefetch
    nixos-rebuild
    nixos-rebuild-ng
  ];

  # Add symlink to flake source that built the current gen
  # https://www.reddit.com/r/NixOS/comments/16t2njf/small_trick_for_people_using_nixos_with_flakes/
  environment.etc."nixos-source".source = ./../..;

  # https://nixos.wiki/wiki/FAQ/When_do_I_update_stateVersion
  system = {
    stateVersion = "25.11";
    # autoUpgrade = {
    #   enable = true;
    #   channel = "https://nixos.org/channels/nixos-23.05";
    # };
    activationScripts = lib.mkIf (config.hardware.type != "rpi") {
      nixos-needsreboot = {
        supportsDryActivation = true;
        text = "${
          lib.getExe inputs.nixos-needsreboot.packages.${pkgs.stdenv.hostPlatform.system}.default
        } \"$systemConfig\" || true";
      };
    };
  };
}
