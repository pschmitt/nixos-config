{
  description = "pschmitt's nix collection";

  inputs = {
    # Nixpkgs
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable"; # unstable by default
    nixpkgs-stable.url = "github:nixos/nixpkgs/nixos-24.05";
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixos-unstable";
    nixpkgs-master.url = "github:nixos/nixpkgs/master";

    # attic = {
    #   url = "github:zhaofengli/attic";
    #   inputs.nixpkgs.follows = "nixpkgs";
    # };

    catppuccin.url = "github:catppuccin/nix";

    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    fenix = {
      url = "github:nix-community/fenix/monthly";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # flake-registry = {
    #   url = "github:NixOS/flake-registry";
    #   flake = false;
    # };

    # flake-utils = {
    #   url = "github:numtide/flake-utils";
    # };

    flatpaks = {
      # https://github.com/GermanBread/declarative-flatpak/blob/dev/docs/branches.md
      url = "github:GermanBread/declarative-flatpak/stable-v3";
      # NOTE Do *not* override nixpkgs, it is not supported
    };

    ghostty = {
      url = "github:ghostty-org/ghostty";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    hardware.url = "github:nixos/nixos-hardware";

    home-manager = {
      url = "github:nix-community/home-manager";
      # url = "github:nix-community/home-manager/release-23.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    hacompanion = {
      url = "github:tobias-kuendig/hacompanion";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Hyprland and cie {{{
    hyprland = {
      type = "git";
      url = "https://github.com/hyprwm/Hyprland";
      # https://github.com/hyprwm/Hyprland/releases
      ref = "refs/tags/v0.48.1";
      # git ls-remote --tags https://github.com/hyprwm/Hyprland | sort --version-sort -k 2 | tail -1 | awk '{ print $1 }'
      # rev = "4520b30d498daca8079365bdb909a8dea38e8d55";
      submodules = true;
      inputs.nixpkgs.follows = "nixpkgs";
    };

    hypridle = {
      url = "github:hyprwm/hypridle";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    hyprlock = {
      url = "github:hyprwm/hyprlock";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # hyprland end }}}

    lan-mouse = {
      url = "github:feschber/lan-mouse";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    neovim-nightly = {
      url = "github:nix-community/neovim-nightly-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nix-index-database = {
      url = "github:nix-community/nix-index-database";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixpkgs-wayland = {
      url = "github:nix-community/nixpkgs-wayland";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # the myl family
    myl = {
      url = "github:pschmitt/myl";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    myl-discovery = {
      url = "github:pschmitt/myl-discovery";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    firefox-addons = {
      url = "gitlab:rycee/nur-expressions?dir=pkgs/firefox-addons";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    sendmyl = {
      url = "github:pschmitt/sendmyl";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    tdc = {
      url = "github:pschmitt/tdc";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    pre-commit-hooks = {
      url = "github:cachix/pre-commit-hooks.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    simple-nixos-mailserver = {
      url = "gitlab:simple-nixos-mailserver/nixos-mailserver";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    snapd = {
      url = "github:io12/nix-snapd";
      # url = "/etc/nixos/nix-snapd.git";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    srvos = {
      url = "github:nix-community/srvos";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    update-systemd-resolved = {
      url = "github:jonathanio/update-systemd-resolved";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    wezterm = {
      url = "github:wez/wezterm?dir=nix";
      # https://github.com/NixOS/nixpkgs/issues/348832
      # inputs.nixpkgs.follows = "nixpkgs";
    };

    zen-browser = {
      url = "github:0xc000022070/zen-browser-flake";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # zjstatus = {
    #   url = "github:dj95/zjstatus";
    #   inputs.nixpkgs.follows = "nixpkgs";
    # };

    # HOTFIXES: Overrides, pending PRs, etc
    # droidcam-obs.url = "github:NixOS/nixpkgs?ref=refs/pull/382559/head";
  };

  outputs =
    {
      self,
      catppuccin,
      disko,
      flatpaks,
      home-manager,
      nix-index-database,
      nixpkgs,
      simple-nixos-mailserver,
      snapd,
      sops-nix,
      srvos,
      update-systemd-resolved,
      ...
    }@inputs:
    let
      inherit (self) outputs;
      forAllSystems = nixpkgs.lib.genAttrs [
        "aarch64-linux"
        "i686-linux"
        "x86_64-linux"
        "aarch64-darwin"
        "x86_64-darwin"
      ];

      commonModules = [
        ./modules/custom.nix
        ./modules/luks-ssh-unlock.nix

        disko.nixosModules.disko
        flatpaks.nixosModules.declarative-flatpak
        nix-index-database.nixosModules.nix-index
        sops-nix.nixosModules.sops
        update-systemd-resolved.nixosModules.update-systemd-resolved
      ];

      nixosSystemFor =
        system: hostname: configOptions:
        nixpkgs.lib.nixosSystem {
          inherit system;
          specialArgs = {
            inherit inputs outputs configOptions;
          };
          modules =
            commonModules
            ++ [ ./hosts/${hostname} ]
            ++ nixpkgs.lib.optionals (!(configOptions.server or false)) [
              ./home-manager
              catppuccin.nixosModules.catppuccin
            ]
            ++ nixpkgs.lib.optionals (configOptions.server or true) [
              simple-nixos-mailserver.nixosModule
              srvos.nixosModules.mixins-terminfo
            ]
            ++ nixpkgs.lib.optionals (configOptions.snapd or false) [ snapd.nixosModules.default ];
        };
    in
    {
      # Your custom packages
      # Accessible through 'nix build', 'nix shell', etc
      packages = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        import ./pkgs { inherit pkgs; }
      );

      checks = forAllSystems (system: {
        pre-commit-check = inputs.pre-commit-hooks.lib.${system}.run {
          src = ./.;
          hooks = {
            nixfmt-rfc-style.enable = true;
            statix.enable = false;
            pre-commit-hook-ensure-sops = {
              enable = true;
              files = ".+.sops.yaml$";
            };
          };
        };
      });

      # Devshell for bootstrapping
      # Accessible through 'nix develop' or 'nix-shell' (legacy)
      devShells = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          checks = self.checks.${system};
        in
        import ./shell.nix { inherit pkgs checks; }
      );

      # Your custom packages and modifications, exported as overlays
      overlays = import ./overlays { inherit inputs; };

      # Reusable nixos modules you might want to export
      # These are usually stuff you would upstream into nixpkgs
      # nixosModules = import ./modules/nixos;

      # Reusable home-manager modules you might want to export
      # These are usually stuff you would upstream into home-manager
      # homeManagerModules = import ./modules/home-manager;

      # NixOS configuration entrypoint
      # Available through 'nixos-rebuild --flake .#your-hostname'
      nixosConfigurations = {
        x13 = nixosSystemFor "x86_64-linux" "x13" { laptop = true; };
        ge2 = nixosSystemFor "x86_64-linux" "ge2" { laptop = true; };
        lrz = nixosSystemFor "x86_64-linux" "lrz" { server = true; };
        rofl-03 = nixosSystemFor "x86_64-linux" "rofl-03" { server = true; };
        rofl-06 = nixosSystemFor "x86_64-linux" "rofl-06" { server = true; };
        rofl-08 = nixosSystemFor "x86_64-linux" "rofl-08" { server = true; };
        rofl-09 = nixosSystemFor "x86_64-linux" "rofl-09" { server = true; };
        oci-03 = nixosSystemFor "aarch64-linux" "oci-03" {
          server = true;
          snapd = true;
        };
        iso = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [
            "${nixpkgs}/nixos/modules/installer/cd-dvd/channel.nix"
            "${nixpkgs}/nixos/modules/installer/cd-dvd/installation-cd-minimal.nix"
            ./hosts/iso
            ./modules/custom.nix
          ];
        };
        iso-xmr = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [
            "${nixpkgs}/nixos/modules/installer/cd-dvd/channel.nix"
            "${nixpkgs}/nixos/modules/installer/cd-dvd/installation-cd-minimal.nix"
            ./hosts/iso-xmr
            ./modules/custom.nix
          ];
        };
      };
    };
}
