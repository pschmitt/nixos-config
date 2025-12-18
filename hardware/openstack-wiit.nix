{
  lib,
  config,
  ...
}:
{
  config = lib.mkIf (config.hardware.serverType == "openstack") {
    hardware.kvmGuest = true;

    nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
    custom.netbirdSetupKey = lib.mkForce "optimist";

    boot = {
      initrd = {
        # From nixpkgs' `profiles/qemu-guest.nix`
        availableKernelModules = [
          "virtio_net"
          "virtio_pci"
          "virtio_mmio"
          "virtio_blk"
          "virtio_scsi"
          "9p"
          "9pnet_virtio"
        ]
        ++ [
          "ata_piix"
          "uhci_hcd"
          "xen_blkfront"
          "vmw_pvscsi"
          # Below is required for ssh in initrd
          "virtio_pci"
          "virtio_net"
        ];
        kernelModules = [
          "virtio_balloon"
          "virtio_console"
          "virtio_rng"
          "virtio_gpu"
          "nvme"
        ];
      };
      supportedFilesystems = [ "btrfs" ];
    };

    # HACK Fix netbird port forwarding
    networking.nat = {
      enable = true;
      externalInterface = "ens3";
    };
  };
}
