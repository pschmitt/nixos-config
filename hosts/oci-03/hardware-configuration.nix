# Inspired by:
# https://gist.github.com/ghuntley/14ada2d9934c09ae0f3677ac4048abfc
{ modulesPath, ... }:
{
  imports = [ (modulesPath + "/profiles/qemu-guest.nix") ];
  boot.initrd.availableKernelModules = [
    "xhci_pci"
    "virtio_scsi"
  ];

  boot.supportedFilesystems = [ "btrfs" ];

  fileSystems."/" = {
    # device = "/dev/sda1";  # set by disko
    fsType = "btrfs";
    options = [
      "subvol=@root"
      "compress=zstd"
    ];
  };

  fileSystems."/home" = {
    fsType = "btrfs";
    options = [
      "subvol=@home"
      "compress=zstd"
    ];
  };

  fileSystems."/nix" = {
    fsType = "btrfs";
    options = [
      "subvol=@nix"
      "compress=zstd"
    ];
  };

  # NOTE This is set by disko already
  # boot.initrd.luks.devices."encrypted".device = "/dev/sda1";
}
