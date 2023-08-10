# Do not modify this file!  It was generated by ‘nixos-generate-config’
# and may be overwritten by future invocations.  Please make changes
# to /etc/nixos/configuration.nix instead.
{ config, lib, pkgs, modulesPath, ... }:

{
  imports = [ (modulesPath + "/installer/scan/not-detected.nix") ];

  # Attempt to fix keyboard in initrd on x13
  # kernelParams = [ "i8042.notimeout=1" "i8042.dumbkbd=1" "i8042.reset=1" "i8042.direct=1" ];
  # boot.initrd.availableKernelModules = ["i8042"];
  # boot.initrd.kernelModules = ["i8042"];

  # https://bugs.launchpad.net/ubuntu/+source/linux-source-2.6.17/+bug/76881
  boot.kernelParams = [ "i8042.probe_defer=1" ];
  # DIRTYFIX Force reload i8042 module after boot
  # systemd.services.fix-keyboard = {
  #   wantedBy = [ "multi-user.target" ];
  #   description = "Fix keyboard by reloading i8042";
  #   serviceConfig = {
  #     Type = "oneshot";
  #     ExecStartPre- = "${pkgs.kmod}/bin/rmmod i8042";
  #     ExecStart = "${pkgs.kmod}/bin/modprobe i8042";
  #   };
  # };

  boot.initrd.availableKernelModules =
    [ "nvme" "ehci_pci" "xhci_pci" "uas" "sd_mod" "rtsx_pci_sdmmc" ];
  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [ "kvm-amd" ];
  boot.extraModulePackages = [ ];

  fileSystems."/" = {
    device = "/dev/disk/by-uuid/76f0b042-784e-42c4-afbd-0985100e6626";
    fsType = "btrfs";
    options = [ "subvol=@root" "compress=zstd" ];
  };

  boot.initrd.luks.devices."encrypted".device =
    "/dev/disk/by-uuid/d3725a76-331b-4658-a160-10d89d51c80e";

  fileSystems."/boot" = {
    device = "/dev/disk/by-uuid/5FDA-8CAF";
    fsType = "vfat";
  };

  fileSystems."/home" = {
    device = "/dev/disk/by-uuid/76f0b042-784e-42c4-afbd-0985100e6626";
    fsType = "btrfs";
    options = [ "subvol=@home" "compress=zstd" ];
  };

  fileSystems."/nix" = {
    device = "/dev/disk/by-uuid/76f0b042-784e-42c4-afbd-0985100e6626";
    fsType = "btrfs";
    options = [ "subvol=@nix" "compress=zstd" "noatime" ];
  };

  swapDevices = [ ];

  # Enables DHCP on each ethernet and wireless interface. In case of scripted networking
  # (the default) this is the recommended approach. When using systemd-networkd it's
  # still possible to use this option, but it's recommended to use it in conjunction
  # with explicit per-interface declarations with `networking.interfaces.<interface>.useDHCP`.
  networking.useDHCP = lib.mkDefault true;
  # networking.interfaces.docker0.useDHCP = lib.mkDefault true;
  # networking.interfaces.enp2s0f0.useDHCP = lib.mkDefault true;
  # networking.interfaces.wlp3s0.useDHCP = lib.mkDefault true;

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  hardware.cpu.amd.updateMicrocode =
    lib.mkDefault config.hardware.enableRedistributableFirmware;
}
