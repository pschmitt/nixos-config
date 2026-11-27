{
  config,
  pkgs,
  ...
}:
let
  cfg = config.services.home-assistant-vm;
  virsh = "${pkgs.libvirt}/bin/virsh -c qemu:///system";
in
{
  imports = [ ../../services/home-assistant-vm.nix ];

  services = {
    home-assistant-vm = {
      enable = true;
      physicalInterface = "eno1";
      # bridgeMac and macAddress are set in the private input.
      autostart = true;
    };

    # The VM runs on this host: mount its config over the local bridge instead
    # of the VPN name (unreachable from the hypervisor itself).
    home-assistant.sshfs.host = config.networking.homeLan.homeAssistant;

    monit.checks = {
      "libvirt ${cfg.domainName}" = {
        type = "process";
        pidfile = "/var/run/libvirt/qemu/${cfg.domainName}.pid";
        conditions = ''
          start program "${virsh} start ${cfg.domainName}"
          stop program "${virsh} stop ${cfg.domainName}"
        '';
      };

      "libvirt ${cfg.domainName} (net)" = {
        type = "host";
        address = config.networking.homeLan.homeAssistant;
        conditions = ''
          start program "${virsh} start ${cfg.domainName}"
          stop program "${virsh} stop ${cfg.domainName}"
          if failed icmp type echo count 5 with timeout 30 seconds then restart
        '';
      };

      hass-fnuc = {
        type = "host";
        address = config.networking.homeLan.homeAssistant;
        conditions = ''
          if failed port 8123 for 5 cycles then alert
          if failed port 1883 for 5 cycles then alert
          if failed port 8883 for 5 cycles then alert
        '';
      };
    };
  };
}
