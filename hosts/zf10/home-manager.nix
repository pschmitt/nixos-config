{ inputs, outputs, ... }:
{
  home-manager = {
    backupFileExtension = "hm-backup";
    extraSpecialArgs = {
      inherit inputs outputs;
      hostname = "zf10";
    };
    useGlobalPkgs = true;
    config = {
      imports = [
        ../../home-manager/nix-on-droid.nix
        (inputs.nixos-config-private.outPath + "/hm/hosts/zf10.nix")
      ];
      home.stateVersion = "25.11";
    };
  };
}
