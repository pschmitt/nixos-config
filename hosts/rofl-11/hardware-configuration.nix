{ modulesPath, ... }:
{
  imports = [
    (modulesPath + "/profiles/qemu-guest.nix")
    ./disk-config.nix
    ./luks-data.nix
  ];

  boot = {
    initrd = {
      availableKernelModules = [
        "ata_piix"
        "uhci_hcd"
        "xen_blkfront"
        "vmw_pvscsi"
        # Below is required for ssh in initrd
        "virtio_pci"
        "virtio_net"
      ];
      kernelModules = [ "nvme" ];
    };
    supportedFilesystems = [ "btrfs" ];
  };

  fileSystems = {
    "/" = {
      # device = "/dev/sda1";  # set by disko
      fsType = "btrfs";
      options = [
        "subvol=@root"
        "compress=zstd"
      ];
    };

    "/home" = {
      fsType = "btrfs";
      options = [
        "subvol=@home"
        "compress=zstd"
      ];
    };

    "/nix" = {
      fsType = "btrfs";
      options = [
        "subvol=@nix"
        "compress=zstd"
      ];
    };
  };

  # NOTE This is set by disko already
  # boot.initrd.luks.devices."encrypted".device = "/dev/sda1";
}
