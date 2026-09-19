{ pkgs, ... }:
{
  # FNUC-005: Headless virtualization for Home Assistant OS VM
  virtualisation.libvirtd = {
    enable = true;
    onShutdown = "shutdown";
    allowedBridges = [
      "virbr0"
      "hass-br0"
    ];
    qemu = {
      package = pkgs.qemu_kvm;
      swtpm.enable = true;
    };
  };

  # Bridge the HA VM's NIC onto the physical link, for allowedBridges above.
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

  environment.systemPackages = with pkgs; [
    libvirt
    qemu_kvm
    (writeShellScriptBin "define-ha-vm" ''
      exec ${pkgs.libvirt}/bin/virsh define ${./home-assistant.xml}
    '')
  ];
}
