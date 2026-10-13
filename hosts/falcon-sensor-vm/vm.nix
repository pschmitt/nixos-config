{ lib, ... }:
{
  # Only ever run as `system.build.vm`, whose qemu module overrides these.
  # They only make the plain toplevel (built by CI) evaluate.
  fileSystems."/" = {
    device = "/dev/disk/by-label/nixos";
    fsType = "ext4";
  };
  boot.loader.grub.devices = lib.mkDefault [ "nodev" ];

  virtualisation.vmVariant.virtualisation = {
    graphics = false;
    memorySize = 1024;
    cores = 1;
    diskSize = 8192;
    qemu.options = [ "-enable-kvm" ];
    forwardPorts = [
      {
        host.address = "127.0.0.1";
        host.port = 32526;
        guest.port = 22;
      }
    ];
    sharedDirectories.falcon-secrets = {
      source = "/run/falcon-sensor-vm-secrets";
      target = "/run/falcon-secrets";
    };
  };
}
