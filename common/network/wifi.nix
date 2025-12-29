{ lib, config, ... }:

let
  # define your networks once
  nets = {
    home = {
      autoconnect = true;
      priority = 100;
      # interfaceName = "wlp0s20f3";  # optional
      # routeMetric4 = 500;           # optional
      # routeMetric6 = 500;           # optional
    };
    home-wwan = {
      # autoconnect = false; # never auto-connect
      priority = -10;
    };
    home-vpn = {
      # autoconnect = false; # never auto-connect
      priority = -10;
    };
    g4p = {
      priority = -100;
    };
    dieppe = {
      autoconnect = true;
    };
  };

  names = builtins.attrNames nets;
  toEnv = n: lib.toUpper (lib.replaceStrings [ "-" ] [ "_" ] n);

  # SOPS secrets for each net (ssid + psk)
  nmSecrets = lib.listToAttrs (
    lib.concatMap (n: [
      {
        name = "wifi/${n}/ssid";
        value = {
          owner = "root";
          group = "networkmanager";
          mode = "0400";
        };
      }
      {
        name = "wifi/${n}/psk";
        value = {
          owner = "root";
          group = "networkmanager";
          mode = "0400";
        };
      }
    ]) names
  );

  # one env file with placeholders
  envContent =
    lib.concatStringsSep "\n" (
      map (n: ''
        NM_${toEnv n}_SSID=${config.sops.placeholder."wifi/${n}/ssid"}
        NM_${toEnv n}_PSK=${config.sops.placeholder."wifi/${n}/psk"}
      '') names
    )
    + "\n";

  # generate profiles
  nmProfiles = lib.genAttrs names (
    n:
    let
      a = nets.${n};
    in
    {
      connection = {
        id = n;
        type = "wifi";
        autoconnect = a.autoconnect or true;
        "autoconnect-priority" = a.priority or 0;
      }
      // lib.optionalAttrs (a ? interfaceName && a.interfaceName != null) {
        "interface-name" = a.interfaceName;
      };

      wifi = {
        ssid = "$NM_${toEnv n}_SSID";
        mode = "infrastructure";
      };

      wifi-security = {
        auth-alg = "open";
        key-mgmt = "wpa-psk";
        psk = "$NM_${toEnv n}_PSK"; # ends up only in /run keyfile
      };

      ipv4 = {
        method = "auto";
      }
      // lib.optionalAttrs (a ? routeMetric4 && a.routeMetric4 != null) {
        "route-metric" = a.routeMetric4;
      };

      ipv6 = {
        method = "auto";
      }
      // lib.optionalAttrs (a ? routeMetric6 && a.routeMetric6 != null) {
        "route-metric" = a.routeMetric6;
      };
    }
  );
in
{
  networking.networkmanager.enable = true;

  sops.secrets = nmSecrets;

  sops.templates."nm.env" = {
    owner = "root";
    group = "networkmanager";
    mode = "0400";
    content = envContent;
  };

  networking.networkmanager.ensureProfiles = {
    environmentFiles = [ config.sops.templates."nm.env".path ];
    profiles = nmProfiles;
  };
}
