{ lib, ... }:
{
  options = {
    device.type = lib.mkOption {
      type = lib.types.nullOr (
        lib.types.enum [
          "laptop"
          "server"
          "installation-media"
          "rpi"
        ]
      );
      default = null;
      description = "Device category for this host.";
    };

    home-manager.enabled = lib.mkEnableOption "home-manager for this host";
  };
}
