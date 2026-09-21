{ config, pkgs, ... }:
{
  networking = {
    hostName = "fnuc";
    firewall.enable = false;

    # Wake-on-LAN over the wired NIC, so the box can be woken remotely from
    # ATX standby.
    interfaces.eno1.wakeOnLan.enable = true;

    wireless = {
      enable = true;
      interfaces = [ "wlp0s20f3" ];
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

  systemd.network.networks."40-wlp0s20f3" = {
    matchConfig.Name = "wlp0s20f3";
    networkConfig = {
      DHCP = "yes";
      IPv6PrivacyExtensions = "kernel";
    };
    dhcpV4Config.RouteMetric = 2048;
    ipv6AcceptRAConfig.RouteMetric = 2048;
  };

  # The onboard Intel I219-LM occasionally wedges its TX ring, surfacing as
  # e1000e "Detected Hardware Unit Hang" and taking down the host and its
  # bridged HA VM until a hard reboot. Disabling EEE alone did not stop the
  # recurrence (still hit it after ~20h uptime with EEE off), so also
  # disable TSO/GSO/GRO segmentation offload, the most commonly effective
  # workaround reported for this I219 TX-hang bug. Keep both disabled
  # before systemd-networkd configures the interface.
  systemd.services.e1000e-eno1-workarounds = {
    description = "Disable EEE and segmentation offload on fnuc's Intel e1000e interface";
    wantedBy = [
      "network-pre.target"
      "sys-subsystem-net-devices-eno1.device"
    ];
    before = [ "network-pre.target" ];
    after = [ "sys-subsystem-net-devices-eno1.device" ];
    bindsTo = [ "sys-subsystem-net-devices-eno1.device" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = [
        "${pkgs.ethtool}/bin/ethtool --set-eee eno1 eee off"
        "${pkgs.ethtool}/bin/ethtool -K eno1 tso off gso off gro off"
      ];
    };
  };
}
