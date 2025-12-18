{ lib, config, ... }:
{
  imports = [
    ../hardware/watchdog.nix
  ];

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

      serverType = lib.mkOption {
        type = lib.types.nullOr (
          lib.types.enum [
            "openstack"
            "oci"
            "bare-metal"
          ]
        );
        default = null;
        description = "Server environment type (cloud/hardware).";
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

      fprintd.autoreset = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to automatically USB reset the fingerprint reader when fprintd does not detect it.";
        };

        deviceName = lib.mkOption {
          type = lib.types.str;
          default = "Fingerprint";
          description = "USB device name (as shown by lsusb) of the fingerprint reader.";
        };
      };

      kvmGuest = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Whether this is cloud-based server";
      };

      watchdog = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = config.hardware.type == "server";
          defaultText = "hardware.type == \"server\"";
          description = "Enable watchdog support for this host.";
        };

        implementation = lib.mkOption {
          type = lib.types.enum [
            "hardware"
            "softdog"
            "virtio"
          ];
          default = if config.hardware.type == "rpi" then "hardware" else "softdog";
          defaultText = "if hardware.type == \"rpi\" then \"hardware\" else \"softdog\"";
          description = "Watchdog driver to use";
        };
      };
    };
  };
}
