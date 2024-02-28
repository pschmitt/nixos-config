{
  description = "pschmitt's nix collection";

  inputs = {
    # Nixpkgs
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable"; # unstable by default
    nixpkgs-stable.url = "github:nixos/nixpkgs/nixos-23.11";
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixos-unstable";
    nixpkgs-master.url = "github:nixos/nixpkgs/master";

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

    hyprland = {
      # main branch
      url = "github:hyprwm/Hyprland/v0.36.0";
      # good (window screen sharing) - newer
      # url = "github:hyprwm/Hyprland/8c3613632a6ccebf9fb797ec756ecfce99514eec";
      # good (window screen sharing)
      # url = "github:hyprwm/Hyprland/94aeb06d6ba14d403c46b52d1d2e397acb5906a4";
      # good (window screen sharing)
      # url "github:hyprwm/Hyprland/dfcfb92ec611345848f3840d34d66b8501e6367c";

      inputs.nixpkgs.follows = "nixpkgs";
    };

    hypridle = {
      url = "github:hyprwm/hypridle/v0.1.0";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    hyprlock = {
      url = "github:hyprwm/hyprlock/v0.1.0";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # FIXME Remove this once hyprlang 0.4.0 is available in nixpkgs
    # https://github.com/NixOS/nixpkgs/pull/289630
    hyprlang = {
      url = "github:hyprwm/hyprlang/v0.4.0";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    xdph = {
      # url = "github:hyprwm/xdg-desktop-portal-hyprland/v1.3.1";
      url = "github:hyprwm/xdg-desktop-portal-hyprland";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixpkgs-wayland = {
      url = "github:nix-community/nixpkgs-wayland";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    flatpaks = {
      url = "github:GermanBread/declarative-flatpak/stable";
      # NOTE Do *not* override nixpkgs, it is not supported
    };

    neovim = {
      url = "github:neovim/neovim/c8a27bae3faeaca137e5f67b1b052ce0f0225b36?dir=contrib";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    attic = {
      url = "github:zhaofengli/attic";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    zjstatus = {
      url = "github:dj95/zjstatus";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, home-manager, flatpaks, nix-index-database, agenix, nur, ... }@inputs:
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
        agenix.nixosModules.default
        flatpaks.nixosModules.default
        nix-index-database.nixosModules.nix-index
        nur.nixosModules.nur
        ./home-manager
      ];

      nixosSystemFor = system: hostname: nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = { inherit inputs outputs; };
        modules = commonModules ++ [ ./hosts/${hostname} ];
      };
    in
    {
      # Your custom packages
      # Acessible through 'nix build', 'nix shell', etc
      packages = forAllSystems (system:
        let pkgs = nixpkgs.legacyPackages.${system};
        in import ./pkgs { inherit pkgs; }
      );

      # Devshell for bootstrapping
      # Acessible through 'nix develop' or 'nix-shell' (legacy)
      devShells = forAllSystems (system:
        let pkgs = nixpkgs.legacyPackages.${system};
        in import ./shell.nix { inherit pkgs; }
      );

      # Your custom packages and modifications, exported as overlays
      overlays = import ./overlays { inherit inputs; };

      # Reusable nixos modules you might want to export
      # These are usually stuff you would upstream into nixpkgs
      nixosModules = import ./modules/nixos;

      # Reusable home-manager modules you might want to export
      # These are usually stuff you would upstream into home-manager
      # homeManagerModules = import ./modules/home-manager;

      # NixOS configuration entrypoint
      # Available through 'nixos-rebuild --flake .#your-hostname'
      nixosConfigurations = {
        x13 = nixosSystemFor "x86_64-linux" "x13";
        ge2 = nixosSystemFor "x86_64-linux" "ge2";
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
