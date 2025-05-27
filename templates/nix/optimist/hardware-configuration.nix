{ modulesPath, ... }:
{
  imports = [ (modulesPath + "/profiles/qemu-guest.nix") ];
  boot.initrd.availableKernelModules = [
    "ata_piix"
    "uhci_hcd"
    "xen_blkfront"
    "vmw_pvscsi"
  ];
  boot.initrd.kernelModules = [ "nvme" ];

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
