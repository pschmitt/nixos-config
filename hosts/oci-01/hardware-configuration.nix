{ modulesPath, ... }:
{
  imports = [ (modulesPath + "/profiles/qemu-guest.nix") ];

  boot = {
    initrd.availableKernelModules = [
      "xhci_pci"
      "virtio_scsi"
    ];
    supportedFilesystems = [ "btrfs" ];
  };

  fileSystems = {
    "/" = {
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
}
