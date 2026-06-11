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
    # Import-gating facts go through specialArgs (not config) so home.nix can
    # branch its `imports` without a config-in-imports infinite recursion.
    extraSpecialArgs = {
      inherit inputs hostname;
      guiEnable = config.services.xserver.enable;
      bluetoothEnable = config.hardware.bluetooth.enable;
    };

    useGlobalPkgs = true;
    useUserPackages = true;

    users.${config.mainUser.username} = {
      imports = [
        ./home.nix
      ];

      # Bridge: feed system facts from the NixOS config into the (osConfig-free)
      # home config. Standalone hosts set these explicitly instead.
      inherit (config) mainUser domains;
      host = {
        sopsFile = config.custom.sopsFile;
        sopsDefaultFile = config.sops.defaultSopsFile;
        highDpi = config.hardware.highDpi;
        nvidiaPrimeOffload = config.hardware.nvidia.prime.offload.enable;
        iioSensor = config.hardware.sensor.iio.enable;
        provisionSshKeys = true;
        uid =
          let
            u = config.users.users.${config.mainUser.username}.uid;
          in
          if u == null then 1000 else u;
        stateVersion = config.system.stateVersion;
      };
    };
  };
}
