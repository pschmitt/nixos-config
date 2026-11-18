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
        ({ config, lib, ... }: {
          sops.defaultSopsFile = lib.mkDefault (
            inputs.nixos-config-private.outPath + "/hosts/${hostname}/secrets.sops.yaml"
          );
          sops.age.sshKeyPaths = lib.mkDefault [ "${config.home.homeDirectory}/.ssh/id_ed25519" ];
        })
      ];
    };
in
{
  zf10 = mkHome "zf10";
  p11 = mkHome "p11";
}
