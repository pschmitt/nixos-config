{ lib, modulesPath, ... }:
{
  imports = [ (modulesPath + "/profiles/qemu-guest.nix") ];

  hardware.kvmGuest = true;

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  custom.netbirdSetupKey = lib.mkForce "optimist";

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

  # TODO Put the respective internalInterfaces values into the netbird.nix
  # and tailscale.nix files
  # HACK Fix netbird port forwarding
  networking.nat = {
    enable = true;
    externalInterface = "ens3";
    # internalIPs = [
    #   # Netbird subnet
    #   "100.122.0.0/16"
    #   # Tailscale
    #   "100.64.0.0/10"
    # ];
    internalInterfaces = [
      # netbird-netbird-io
      "netbird-io"
      # netbird-wiit
      "wiit"
      # default nb interface name
      # "netbird0"
      "wt0"

      # tailscale default interface name
      "tailscale0"
    ];
  };
}
