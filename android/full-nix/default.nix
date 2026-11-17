{ inputs }:
let
  pkgs = import inputs.nixpkgs {
    system = "aarch64-linux";
    config.allowUnfree = true;
    overlays = builtins.attrValues (import ../../overlays { inherit inputs; }) ++ [
      (import ./overlay.nix)
    ];
  };
  mkHome =
    hostname:
    inputs.home-manager.lib.homeManagerConfiguration {
      inherit pkgs;
      extraSpecialArgs = { inherit inputs hostname; };
      modules = [
        ./home.nix
        (../../hosts + "/${hostname}/prompt.nix")
      ];
    };
in
{
  zf10 = mkHome "zf10";
  p11 = mkHome "p11";
}
