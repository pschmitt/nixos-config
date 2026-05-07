{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.initrd.wifi;
  supplicantConfig = "/etc/wpa_supplicant/wpa_supplicant-${cfg.interfaceName}.conf";
  encryptedSecretsPath = "/etc/initrd-wifi.sops.yaml";
  initrdSshAgePrivateKeyPath = "/etc/ssh/initrd/ssh_host_ed25519_key";
  intelWifiFirmware =
    let
      firmwareDir = "${pkgs.linux-firmware}/lib/firmware";
    in
    builtins.filter (lib.hasPrefix "iwlwifi-") (builtins.attrNames (builtins.readDir firmwareDir));
  sopsExtractExpr = key: "[\"" + lib.concatStringsSep "\"][\"" (lib.splitString "/" key) + "\"]";
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
        default = ../../secrets/initrd-wifi.sops.yaml;
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

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        assertions = [
          {
            assertion =
              config.boot.initrd.network.ssh.enable
              && lib.elem initrdSshAgePrivateKeyPath config.boot.initrd.network.ssh.hostKeys;
            message = "initrd.wifi.enable requires boot.initrd.network.ssh.hostKeys to include /etc/ssh/initrd/ssh_host_ed25519_key.";
          }
        ];

        boot.initrd = {
          inherit (cfg) availableKernelModules;
          extraFirmwarePaths = cfg.firmwarePaths;
          secrets = {
            ${encryptedSecretsPath} = cfg.sops.file;
          };

          systemd = {
            packages = [
              pkgs.sops
              pkgs.wpa_supplicant
            ];
            initrdBin = [
              pkgs.sops
              pkgs.wpa_supplicant
            ];
            targets.initrd.wants = [ "wpa_supplicant@${cfg.interfaceName}.service" ];
            services."wpa_supplicant@".unitConfig.DefaultDependencies = false;
            services.initrdWifiSupplicant = {
              unitConfig.DefaultDependencies = false;
              before = [ "wpa_supplicant@${cfg.interfaceName}.service" ];
              wantedBy = [ "initrd.target" ];
              serviceConfig = {
                Type = "oneshot";
                RemainAfterExit = true;
              };
              script = ''
                ${pkgs.coreutils}/bin/install -d -m 0755 /etc/wpa_supplicant

                ssid="$(
                  HOME=/var/empty \
                    SOPS_AGE_SSH_PRIVATE_KEY_FILE=${initrdSshAgePrivateKeyPath} \
                    ${pkgs.sops}/bin/sops --decrypt \
                    --extract '${sopsExtractExpr cfg.sops.keys.ssid}' \
                    ${lib.escapeShellArg encryptedSecretsPath}
                )"
                psk="$(
                  HOME=/var/empty \
                    SOPS_AGE_SSH_PRIVATE_KEY_FILE=${initrdSshAgePrivateKeyPath} \
                    ${pkgs.sops}/bin/sops --decrypt \
                    --extract '${sopsExtractExpr cfg.sops.keys.psk}' \
                    ${lib.escapeShellArg encryptedSecretsPath}
                )"

                ${pkgs.wpa_supplicant}/bin/wpa_passphrase "$ssid" "$psk" > ${lib.escapeShellArg supplicantConfig}
                ${pkgs.coreutils}/bin/chmod 0400 ${lib.escapeShellArg supplicantConfig}
              '';
            };

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
    ]
  );
}
