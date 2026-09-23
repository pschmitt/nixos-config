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
  encryptedSecretsSourcePath = "/.initrd-secrets${encryptedSecretsPath}";
  initrdSshAgePrivateKeySourcePath = "/.initrd-secrets${initrdSshAgePrivateKeyPath}";
  sopsExtractExpr = key: "[\"" + lib.concatStringsSep "\"][\"" (lib.splitString "/" key) + "\"]";
in
{
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
              pkgs.gnused
              pkgs.sops
              pkgs.ssh-to-age
              pkgs.wpa_supplicant
            ];
            initrdBin = [
              pkgs.gnused
              pkgs.sops
              pkgs.ssh-to-age
              pkgs.wpa_supplicant
            ];
            targets.initrd.wants = [ "wpa_supplicant@${cfg.interfaceName}.service" ];
            services."wpa_supplicant@".unitConfig = {
              DefaultDependencies = false;
              Requires = [ "initrdWifiSupplicant.service" ];
              After = [ "initrdWifiSupplicant.service" ];
            };
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
                ${pkgs.ssh-to-age}/bin/ssh-to-age \
                  -private-key \
                  -i ${lib.escapeShellArg initrdSshAgePrivateKeySourcePath} \
                  -o /run/initrd-wifi.age-key
                ${pkgs.coreutils}/bin/chmod 0400 /run/initrd-wifi.age-key

                ssid="$(
                  HOME=/var/empty \
                    SOPS_AGE_KEY_FILE=/run/initrd-wifi.age-key \
                    ${pkgs.sops}/bin/sops --decrypt \
                    --extract '${sopsExtractExpr cfg.sops.keys.ssid}' \
                    ${lib.escapeShellArg encryptedSecretsSourcePath}
                )"
                psk="$(
                  HOME=/var/empty \
                    SOPS_AGE_KEY_FILE=/run/initrd-wifi.age-key \
                    ${pkgs.sops}/bin/sops --decrypt \
                    --extract '${sopsExtractExpr cfg.sops.keys.psk}' \
                    ${lib.escapeShellArg encryptedSecretsSourcePath}
                )"

                ${pkgs.wpa_supplicant}/bin/wpa_passphrase "$ssid" "$psk" > ${lib.escapeShellArg supplicantConfig}
                ${lib.optionalString cfg.hidden ''
                  ${pkgs.gnused}/bin/sed -i '/^[[:space:]]*ssid=/a\    scan_ssid=1' ${lib.escapeShellArg supplicantConfig}
                ''}
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
