{ lib, ... }:
{
  options = {
    hardware =
      let
        deviceType = lib.types.nullOr (
          lib.types.enum [
            "laptop"
            "server"
            "installation-media"
            "rpi"
          ]
        );
      in
      {
        type = lib.mkOption {
          type = deviceType;
          default = null;
          description = "Device category for this host.";
        };

        biosBoot = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Use BIOS instead of UEFI";
        };

        kvmGuest = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Whether this is cloud-based server";
        };

        highDpi = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether this host has a high DPI screen";
        };

        server = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether or not this is a server";
        };

        cattle = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Whether this is a cattle/throw-away server";
        };
      };
  };
}
