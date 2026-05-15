{ config, ... }:
{
  networking.networkmanager.ensureProfiles = {
    environmentFiles = [ config.sops.templates."nm.env".path ];
    profiles = {
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
