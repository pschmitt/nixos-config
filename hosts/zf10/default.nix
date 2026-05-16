{
  inputs,
  outputs,
  ...
}:
{
  environment.etcBackupExtension = ".bak";

  nix = {
    extraOptions = ''
      experimental-features = nix-command flakes
    '';

    registry = {
      nixos-config.flake = inputs.self;
      nixpkgs.flake = inputs.nixpkgs;
    };
  };

  home-manager = {
    backupFileExtension = "hm-backup";
    extraSpecialArgs = {
      inherit inputs outputs;
    };
    useGlobalPkgs = true;
    config = {
      imports = [
        ../../home-manager/nix-on-droid.nix
      ];

      home.stateVersion = "25.11";
    };
  };

  system.stateVersion = "24.05";
}
