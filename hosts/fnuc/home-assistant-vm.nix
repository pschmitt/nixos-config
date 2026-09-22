{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.home-assistant-vm;
  virsh = "${pkgs.libvirt}/bin/virsh -c qemu:///system";
in
{
  imports = [ ../../services/home-assistant-vm.nix ];

  services.home-assistant-vm = {
    enable = true;
    physicalInterface = "eno1";
    bridgeMac = "1c:69:7a:0f:e5:fe";
    domainXml = ./home-assistant.xml;
    autostart = true;
  };

  services.monit.config = lib.mkAfter ''
    check process "libvirt ${cfg.domainName}" with pidfile /var/run/libvirt/qemu/${cfg.domainName}.pid
      start program "${virsh} start ${cfg.domainName}"
      stop program "${virsh} stop ${cfg.domainName}"

    check host "libvirt ${cfg.domainName} (net)" with address 10.5.1.1
      start program "${virsh} start ${cfg.domainName}"
      stop program "${virsh} stop ${cfg.domainName}"
      if failed icmp type echo count 5 with timeout 30 seconds then restart

    check host "hass-fnuc" with address 10.5.1.1
      if failed port 8123 for 5 cycles then alert
      if failed port 1883 for 5 cycles then alert
      if failed port 8883 for 5 cycles then alert
  '';
}
