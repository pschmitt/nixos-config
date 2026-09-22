{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  intelWifiFirmware =
    let
      firmwareDir = "${pkgs.linux-firmware}/lib/firmware";
    in
    builtins.filter (lib.hasPrefix "iwlwifi-") (builtins.attrNames (builtins.readDir firmwareDir));
in
{
  options.initrd.wifi = {
    enable = lib.mkEnableOption "Wi-Fi connectivity in initrd";

    interfaceName = lib.mkOption {
      type = lib.types.str;
      default = "wlp0s20f3";
      description = "Wireless interface to use in initrd.";
    };

    hidden = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable active scanning for hidden initrd Wi-Fi SSIDs.";
    };

    sops = {
      file = lib.mkOption {
        type = lib.types.path;
        default = inputs.nixos-config-private.outPath + "/secrets/nixos-initrd-wifi.sops.yaml";
        description = "SOPS file containing the initrd Wi-Fi credentials.";
      };

      keys = {
        ssid = lib.mkOption {
          type = lib.types.str;
          default = "ssid";
          description = "SOPS secret name containing the initrd Wi-Fi SSID.";
        };

        psk = lib.mkOption {
          type = lib.types.str;
          default = "psk";
          description = "SOPS secret name containing the initrd Wi-Fi PSK.";
        };
      };
    };

    availableKernelModules = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "ccm"
        "ctr"
        "iwlmvm"
        "iwlwifi"
      ];
      description = "Kernel modules needed for Wi-Fi in initrd.";
    };

    firmwarePaths = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = intelWifiFirmware;
      description = "Firmware files to include in initrd for the wireless adapter.";
    };
  };
}
