{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.initrd.wifi;
  supplicantConfig = "/etc/wpa_supplicant/wpa_supplicant-${cfg.interfaceName}.conf";
  supplicantTemplateName = "initrd-wifi-${cfg.interfaceName}.conf";
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

    sops = {
      file = lib.mkOption {
        type = lib.types.path;
        default = config.sops.defaultSopsFile;
        description = "SOPS file containing the initrd Wi-Fi credentials.";
      };

      keys = {
        ssid = lib.mkOption {
          type = lib.types.str;
          default = "wifi/initrd/ssid";
          description = "SOPS secret name containing the initrd Wi-Fi SSID.";
        };

        psk = lib.mkOption {
          type = lib.types.str;
          default = "wifi/initrd/psk";
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

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        boot.initrd = {
          inherit (cfg) availableKernelModules;
          extraFirmwarePaths = cfg.firmwarePaths;
          secrets.${supplicantConfig} = config.sops.templates."${supplicantTemplateName}".path;

          systemd = {
            packages = [
              pkgs.wpa_supplicant
            ];
            initrdBin = [
              pkgs.wpa_supplicant
            ];
            targets.initrd.wants = [ "wpa_supplicant@${cfg.interfaceName}.service" ];
            services."wpa_supplicant@".unitConfig.DefaultDependencies = false;

            network = {
              enable = true;
              networks."10-initrd-wifi" = {
                matchConfig.Name = cfg.interfaceName;
                DHCP = "yes";
              };
            };
          };
        };
      }
      {
        sops = {
          secrets.${cfg.sops.keys.ssid} = {
            sopsFile = cfg.sops.file;
          };
          secrets.${cfg.sops.keys.psk} = {
            sopsFile = cfg.sops.file;
          };

          templates.${supplicantTemplateName} = {
            owner = "root";
            group = "root";
            mode = "0400";
            content = ''
              network={
                ssid="${config.sops.placeholder."${cfg.sops.keys.ssid}"}"
                psk="${config.sops.placeholder."${cfg.sops.keys.psk}"}"
              }
            '';
          };
        };

        environment.etc."wpa_supplicant/wpa_supplicant-${cfg.interfaceName}.conf".source =
          config.sops.templates."${supplicantTemplateName}".path;
      }
    ]
  );
}
