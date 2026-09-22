{ config, ... }:
{
  networking.networkmanager.ensureProfiles = {
    environmentFiles = [ config.sops.templates."nm.env".path ];
    profiles = {
      "Auto Ethernet" = {
        connection = {
          id = "Auto Ethernet";
          type = "ethernet";
          autoconnect = true;
        };
        ipv4 = {
          method = "auto";
        };
        ipv6 = {
          method = "auto";
          addr-gen-mode = "stable-privacy";
        };
      };
      "DHCP Server" = {
        connection = {
          id = "DHCP Server";
          type = "ethernet";
          autoconnect = false;
        };
        ipv4 = {
          method = "shared";
        };
        ipv6 = {
          method = "shared";
        };
      };
      "Hotspot" = {
        connection = {
          id = "Hotspot";
          type = "wifi";
          autoconnect = false;
        };
        wifi = {
          mode = "ap";
          ssid = "$NM_HOTSPOT_SSID";
        };
        wifi-security = {
          key-mgmt = "wpa-psk";
          psk = "$NM_HOTSPOT_PSK";
        };
        ipv4 = {
          method = "shared";
        };
        ipv6 = {
          method = "shared";
        };
      };
    };
  };
}
