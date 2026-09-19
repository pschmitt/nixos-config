{ pkgs, ... }:
let
  defineHaVm = pkgs.writeShellApplication {
    name = "define-ha-vm";
    runtimeInputs = [ pkgs.libvirt ];
    text = ''
      virsh -c qemu:///system define ${./home-assistant.xml}
      virsh -c qemu:///system autostart --disable home-assistant
    '';
  };
in
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

  environment.systemPackages = [
    pkgs.libvirt
    pkgs.qemu_kvm
    defineHaVm
  ];

  # Keep the persistent libvirt domain definition in sync with the Nix-managed
  # XML. The VM remains powered off and non-autostarted until migration cutover.
  systemd.services.home-assistant-vm-init = {
    description = "Define the Nix-managed Home Assistant VM domain";
    wantedBy = [ "multi-user.target" ];
    before = [ "home-assistant-vm-guard.service" ];
    wants = [ "libvirtd-config.service" ];
    after = [ "libvirtd-config.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${defineHaVm}/bin/define-ha-vm";
    };
  };
}
