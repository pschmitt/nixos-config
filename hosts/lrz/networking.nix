{ config, ... }:
{
  networking = {
    hostName = "lrz";
    firewall.enable = false;

    wireless = {
      enable = true;
      interfaces = [ "wlp2s0" ];
      secretsFile = config.sops.templates."wpa_supplicant.secrets".path;
      networks."brkn-lan".pskRaw = "ext:wifi_home_psk";
    };
  };

  sops.secrets."wifi/home/psk" = { };

  sops.templates."wpa_supplicant.secrets" = {
    owner = "root";
    group = "wpa_supplicant";
    mode = "0440";
    content = ''
      wifi_home_psk=${config.sops.placeholder."wifi/home/psk"}
    '';
  };
}
