{
  config,
  hostname,
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
      inherit inputs hostname;
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
