{ config, lib, ... }:
{
  imports = [
    ./disk-config.nix
    ./hardware-configuration.nix
    ./home-manager.nix
    ../../profiles/roles/interactive-server.nix
    ../../profiles/network/ha-sshfs.nix
    ../../profiles/roles/homelab-server.nix

    ../../services/browser-mcp-chromium-container.nix
    ../../services/nix-distributed-build.nix

    ./backups.nix
    ./monit.nix
    ./networking.nix
    ./hass-vm.nix
  ];

  services.watchyourlan.interfaces = [
    "hass-br0"
    "wlp0s20f3"
  ];

  systemd.services.nix-daemon.serviceConfig = {
    CPUWeight = 10;
    CPUQuota = "200%";
    IOWeight = 10;
    MemoryHigh = "4G";
    MemoryMax = "6G";
    ManagedOOMMemoryPressure = "kill";
    ManagedOOMMemoryPressureLimit = "40%";
    TasksMax = 4096;
  };

  mainUser.extraAuthorizedKeys = lib.mkAfter [
    # Home Assistant container on hv, used by the KVM USB replug automation.
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKtJvOe/V+obZ1lS2L/qUAUVDUSFapVKin07BUZSHAU7 root@a0d7b954-ssh"
    config.custom.hermes.sshPublicKey
  ];
}
