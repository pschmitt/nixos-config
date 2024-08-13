{
  description = "pschmitt's nix collection";

  inputs = {
    # Nixpkgs
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable"; # unstable by default
    nixpkgs-stable.url = "github:nixos/nixpkgs/nixos-24.05";
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixos-unstable";
    nixpkgs-master.url = "github:nixos/nixpkgs/master";

    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nur.url = "github:nix-community/NUR";
    hardware.url = "github:nixos/nixos-hardware";

    # flake-registry = {
    #   url = "github:NixOS/flake-registry";
    #   flake = false;
    # };
    # flake-utils = {
    #   url = "github:numtide/flake-utils";
    # };

    # Home manager
    home-manager = {
      url = "github:nix-community/home-manager";
      # url = "github:nix-community/home-manager/release-23.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nix-index-database = {
      url = "github:nix-community/nix-index-database";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    agenix = {
      url = "github:ryantm/agenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    hyprland = {
      type = "git";
      url = "https://github.com/hyprwm/Hyprland";
      # v0.42.0
      rev = "9a09eac79b85c846e3a865a9078a3f8ff65a9259";
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

    xdph = {
      url = "github:hyprwm/xdg-desktop-portal-hyprland";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixpkgs-wayland = {
      url = "github:nix-community/nixpkgs-wayland";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    wezterm = {
      url = "github:wez/wezterm?dir=nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    flatpaks = {
      url = "github:GermanBread/declarative-flatpak/stable";
      # NOTE Do *not* override nixpkgs, it is not supported
    };

    neovim-nightly-overlay = {
      url = "github:nix-community/neovim-nightly-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    attic = {
      url = "github:zhaofengli/attic";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # zjstatus = {
    #   url = "github:dj95/zjstatus";
    #   inputs.nixpkgs.follows = "nixpkgs";
    # };

    srvos = {
      url = "github:nix-community/srvos";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nix-snapd = {
      url = "github:io12/nix-snapd";
      # url = "/etc/nixos/nix-snapd.git";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    pre-commit-hooks = {
      url = "github:cachix/pre-commit-hooks.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      agenix,
      disko,
      flatpaks,
      home-manager,
      nix-index-database,
      nix-snapd,
      nixpkgs,
      nur,
      sops-nix,
      srvos,
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
        agenix.nixosModules.default
        disko.nixosModules.disko
        flatpaks.nixosModules.default
        nix-index-database.nixosModules.nix-index
        nur.nixosModules.nur
        sops-nix.nixosModules.sops
        ./modules/custom.nix
        ./modules/luks-ssh-unlock.nix
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
            ++ nixpkgs.lib.optionals (!(configOptions.server or false)) [ ./home-manager ]
            ++ nixpkgs.lib.optionals (configOptions.server or true) [ srvos.nixosModules.mixins-terminfo ]
            ++ nixpkgs.lib.optionals (configOptions.snapd or false) [ nix-snapd.nixosModules.default ];
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

      checks = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          pre-commit-check = inputs.pre-commit-hooks.lib.${system}.run {
            src = ./.;
            hooks = {
              nixfmt = {
                enable = true;
                package = pkgs.nixfmt-rfc-style;
              };
              statix.enable = false;
              pre-commit-hook-ensure-sops = {
                enable = true;
                files = ".+.sops.yaml$";
              };
            };
          };
        }
      );

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
        x13 = nixosSystemFor "x86_64-linux" "x13" { };
        ge2 = nixosSystemFor "x86_64-linux" "ge2" { };
        lrz = nixosSystemFor "x86_64-linux" "lrz" { server = true; };
        rofl-02 = nixosSystemFor "x86_64-linux" "rofl-02" { server = true; };
        rofl-03 = nixosSystemFor "x86_64-linux" "rofl-03" { server = true; };
        rofl-04 = nixosSystemFor "x86_64-linux" "rofl-04" { server = true; };
        rofl-05 = nixosSystemFor "x86_64-linux" "rofl-05" { server = true; };
        oci-03 = nixosSystemFor "aarch64-linux" "oci-03" {
          server = true;
          snapd = true;
        };
        oci-04 = nixosSystemFor "aarch64-linux" "oci-04" {
          server = true;
          snapd = true;
        };
        iso = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [
            ./modules/custom.nix
            ./hosts/iso
            "${nixpkgs}/nixos/modules/installer/cd-dvd/installation-cd-minimal.nix"
            "${nixpkgs}/nixos/modules/installer/cd-dvd/channel.nix"
          ];
        };
      };

      # FIXME Why doesn't this work? The import never happens
      # homeConfigurations = {
      #   "pschmitt@ge2" = home-manager.lib.homeManagerConfiguration {
      #     pkgs = nixpkgs.legacyPackages.x86_64-linux;
      #     extraSpecialArgs = { inherit inputs outputs; };
      #     useGlobalPkgs = true;
      #     useUserPackages = true;
      #     modules = [
      #       # nix-index-database.hmModules.nix-index
      #       ./home-manager/home.nix
      #     ];
      #   };
      # };
    };
}
