{
  lib,
  outputs,
  ...
}:
let
  isoCfg = outputs.nixosConfigurations.iso-graphical;
  inherit (isoCfg.config.system.build) isoImage;
  isoSystem = isoCfg.config.system.build.toplevel;
  isoKernel = "${isoCfg.config.system.build.kernel}/bzImage";
  isoInitrd = "${isoCfg.config.system.build.initialRamdisk}/initrd";
  isoInstallerFileName = "nixos-installer-graphical.iso";
  isoInstallerPath = "${isoImage}/iso/${isoImage.isoName}";
  isoKernelParams = isoCfg.config.boot.kernelParams or [ ];
  isoOptions = lib.concatStringsSep " " (
    [
      "systemConfig=${isoSystem}"
      "init=${isoSystem}/init"
      "findiso=/EFI/nixos-installer/${isoInstallerFileName}"
    ]
    ++ isoKernelParams
  );
  isoRelease =
    if
      isoCfg.config ? system && isoCfg.config.system ? nixos && isoCfg.config.system.nixos ? release
    then
      isoCfg.config.system.nixos.release
    else
      "";
  isoTitleSuffix = lib.optionalString (isoRelease != "") " (${isoRelease})";
  isoEntryLines = [
    "title NixOS Graphical Installer${isoTitleSuffix}"
  ]
  ++ lib.optionals (isoRelease != "") [ "version ${isoRelease}" ]
  ++ [
    "linux /EFI/nixos-installer/linux"
    "initrd /EFI/nixos-installer/initrd"
    "options ${isoOptions}"
  ];
in
{
  boot.loader.systemd-boot = {
    extraEntries."nixos-graphical-installer.conf" = lib.concatStringsSep "\n" isoEntryLines + "\n";
    extraFiles = {
      "EFI/nixos-installer/linux" = isoKernel;
      "EFI/nixos-installer/initrd" = isoInitrd;
      "EFI/nixos-installer/${isoInstallerFileName}" = isoInstallerPath;
    };
  };
}
