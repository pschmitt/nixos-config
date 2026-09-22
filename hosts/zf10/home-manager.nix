{ inputs, outputs, ... }:
{
  home-manager = {
    backupFileExtension = "hm-backup";
    extraSpecialArgs = {
      inherit inputs outputs;
    };
    useGlobalPkgs = true;
    config = {
      imports = [ ../../home-manager/nix-on-droid.nix ];
      home.stateVersion = "25.11";
    };
  };
}
