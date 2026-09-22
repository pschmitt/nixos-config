{ config, lib, ... }:
{
  networking = {
    hostName = lib.strings.trim (builtins.readFile ./HOSTNAME);
    firewall.enable = false;
    wireless = {
      enable = true;
      secretsFile = config.sops.secrets."wifi/psk".path;
      networks."brkn-lan".psk = "@WIFI_HOME_PSK@";
    };
  };

  sops.secrets."wifi/psk" = config.sops.mkHostSecret { };
}
