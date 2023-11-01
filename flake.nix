{
  description = "pschmitt's nix collection";

  inputs = {
    # Nixpkgs
    # nixpkgs.url = "github:nixos/nixpkgs/nixos-23.05";
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable"; # unstable by default
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixos-unstable";
    nixpkgs-master.url = "github:nixos/nixpkgs/master";

    nur.url = "github:nix-community/NUR";

    hardware.url = "github:nixos/nixos-hardware";

    # flake-registry.url = "github:NixOS/flake-registry";
    # flake-registry.flake = false;

    # Home manager
    # home-manager.url = "github:nix-community/home-manager/release-23.05";
    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";

    nix-index-database.url = "github:nix-community/nix-index-database";
    nix-index-database.inputs.nixpkgs.follows = "nixpkgs";

    agenix.url = "github:ryantm/agenix";

    hyprland.url = "github:hyprwm/Hyprland/v0.31.0";
    hyprland.inputs.nixpkgs.follows = "nixpkgs";
    xdph.url = "github:hyprwm/xdg-desktop-portal-hyprland/v1.2.3";
    xdph.inputs.nixpkgs.follows = "nixpkgs";
    # hyprland.url = "github:hyprwm/Hyprland";
    # xdph.url = "github:hyprwm/xdg-desktop-portal-hyprland";
  };

  outputs = { self, nixpkgs, home-manager, agenix, nur, ... }@inputs:
    let
      inherit (self) outputs;
      forAllSystems = nixpkgs.lib.genAttrs [
        "aarch64-linux"
        "i686-linux"
        "x86_64-linux"
        "aarch64-darwin"
        "x86_64-darwin"
      ];
    in
    rec {
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
        x13 = nixpkgs.lib.nixosSystem {
          specialArgs = { inherit inputs outputs; }; # Pass flake inputs to our config
          # > Our main nixos configuration file <
          modules = [
            ./modules/custom.nix
            inputs.nix-index-database.nixosModules.nix-index
            nur.nixosModules.nur
            agenix.nixosModules.default
            ./hosts/x13
          ];
        };
        ge2 = nixpkgs.lib.nixosSystem {
          specialArgs = { inherit inputs outputs; }; # Pass flake inputs to our config
          # > Our main nixos configuration file <
          modules = [
            ./modules/custom.nix
            inputs.nix-index-database.nixosModules.nix-index
            nur.nixosModules.nur
            agenix.nixosModules.default
            ./hosts/ge2
          ];
        };
      };
    };
}
