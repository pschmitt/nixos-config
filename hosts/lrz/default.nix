{ config, ... }:
{
  imports = [
    ./disk-config.nix
    ./hardware-configuration.nix
    ../../profiles/server

    # home-manager configuration (TEST!)
    ../../profiles/gui/linger.nix
  ];

  hardware.biosBoot = false;
  # NOTE avoids setting kernelParams that are only relevant for kvm guests
  # Having this set to true will cause the system to hang on boot and
  # you will *not* be able to enter the luks password on the console
  hardware.kvmGuest = false;

  # Enable networking
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

  systemd.network = {
    netdevs."10-hass-br0" = {
      netdevConfig = {
        Name = "hass-br0";
        Kind = "bridge";
        MACAddress = "6c:4b:90:e4:73:8c";
      };
      bridgeConfig = {
        STP = false;
        MulticastSnooping = true;
      };
    };

    networks = {
      "40-enp1s0f0" = {
        matchConfig.Name = "enp1s0f0";
        networkConfig.Bridge = "hass-br0";
        linkConfig.RequiredForOnline = "enslaved";
      };

      "40-hass-br0" = {
        matchConfig.Name = "hass-br0";
        networkConfig = {
          DHCP = "yes";
          IPv6PrivacyExtensions = "kernel";
        };
        dhcpV4Config.RouteMetric = 1024;
        ipv6AcceptRAConfig.RouteMetric = 1024;
      };
    };
  };

  services.nfs.server = {
    enable = true;
    exports = ''
      /mnt/sda1 10.5.0.0/22(rw,sync,no_subtree_check,no_root_squash,anonuid=1000,anongid=1000,mountpoint)
    '';
  };

  # Never export the underlying root filesystem if the SATA mount is missing.
  systemd.services.nfs-server = {
    unitConfig.RequiresMountsFor = [ "/mnt/sda1" ];
    bindsTo = [ "mnt-sda1.mount" ];
    after = [ "mnt-sda1.mount" ];
  };
}
