{
  config,
  inputs,
  ...
}:
{
  imports = [
    # Import home-manager's NixOS module
    inputs.home-manager.nixosModules.home-manager
  ];

  home-manager = {
    extraSpecialArgs = {
      inherit inputs;
    };

    useGlobalPkgs = true;
    useUserPackages = true;

    users.${config.mainUser.username} = {
      imports = [
        ./home.nix
      ];
    };
  };
}
