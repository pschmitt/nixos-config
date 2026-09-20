{ config, ... }:
{
  networking = {
    hostName = "lrz";
    firewall.enable = false;

    # Wake-on-LAN over the wired NIC, so the box can be woken remotely from
    # ATX standby (the Shelly plug that powers it is left on; power-on is a
    # WOL magic packet, not a mains cycle).
    interfaces.enp1s0f0.wakeOnLan.enable = true;

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
