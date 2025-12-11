{ lib, ... }:
{
  options = {
    hardware = {
      type = lib.mkOption {
        type = lib.types.nullOr (
          lib.types.enum [
            "installation-media"
            "rpi"

            "laptop"
            "server"
          ]
        );
        default = null;
        description = "Device category for this host.";
      };

      biosBoot = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Use BIOS instead of UEFI";
      };

      cattle = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Whether this is a cattle/throw-away server";
      };

      highDpi = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Whether this host has a high DPI screen";
      };

      kvmGuest = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Whether this is cloud-based server";
      };

      server = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Whether or not this is a server";
      };
    };
  };
}
