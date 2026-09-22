{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.home-assistant-vm;

  defineHaVm = pkgs.writeShellApplication {
    name = "define-home-assistant-vm";
    runtimeInputs = [ pkgs.libvirt ];
    text = ''
      virsh -c qemu:///system define ${cfg.domainXml}
      virsh -c qemu:///system ${
        if cfg.autostart then "autostart" else "autostart --disable"
      } ${cfg.domainName}
    '';
  };
in
{
  config = lib.mkIf cfg.enable {
    virtualisation.libvirtd = {
      enable = true;
      onShutdown = "shutdown";
      allowedBridges = [
        "virbr0"
        cfg.bridgeName
      ];
      qemu = {
        package = pkgs.qemu_kvm;
        swtpm.enable = true;
      };
    };

    systemd.network = {
      netdevs."10-${cfg.bridgeName}" = {
        netdevConfig = {
          Name = cfg.bridgeName;
          Kind = "bridge";
        }
        // lib.optionalAttrs (cfg.bridgeMac != null) {
          MACAddress = cfg.bridgeMac;
        };
        bridgeConfig = {
          STP = false;
          MulticastSnooping = true;
        };
      };

      networks = {
        "40-${cfg.physicalInterface}" = {
          matchConfig.Name = cfg.physicalInterface;
          networkConfig = {
            Bridge = cfg.bridgeName;
          };
          linkConfig.RequiredForOnline = "enslaved";
        };

        "40-${cfg.bridgeName}" = {
          matchConfig.Name = cfg.bridgeName;
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

    systemd.services.home-assistant-vm-init = {
      description = "Define the Nix-managed Home Assistant VM domain";
      wantedBy = [ "multi-user.target" ];
      wants = [ "libvirtd-config.service" ];
      after = [ "libvirtd-config.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "${defineHaVm}/bin/define-home-assistant-vm";
      };
    };
  };
}
