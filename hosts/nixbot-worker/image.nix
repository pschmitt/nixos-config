# The OpenStack image: a GPT disk with only an ESP. systemd-boot loads the
# kernel and the netboot initrd, which carries the whole system as squashfs
# (installer/netboot). Nothing else on the disk is unencrypted; disk.nix
# adds the encrypted data partition at boot.
{
  config,
  lib,
  modulesPath,
  pkgs,
  ...
}:
let
  inherit (pkgs.stdenv.hostPlatform) efiArch;
  inherit (config.system) build;
  entry = "nixbot-worker";
in
{
  imports = [
    "${modulesPath}/installer/netboot/netboot.nix"
    "${modulesPath}/image/repart.nix"
  ];

  netboot.squashfsCompression = "zstd -Xcompression-level 6";

  # netboot also claims the image options for its kexec tarball; the disk
  # image is what we ship.
  system.build.image = lib.mkForce config.image.repart.image;
  image = {
    extension = lib.mkForce "raw";
    filePath = lib.mkForce config.image.fileName;

    repart = {
      enable = true;
      name = "nixbot-worker";
      partitions."00-esp" = {
        contents = {
          "/EFI/BOOT/BOOT${lib.toUpper efiArch}.EFI".source =
            "${pkgs.systemd}/lib/systemd/boot/efi/systemd-boot${efiArch}.efi";
          "/EFI/${entry}/kernel".source = "${build.kernel}/${config.system.boot.loader.kernelFile}";
          "/EFI/${entry}/initrd".source = "${build.netbootRamdisk}/initrd";
          "/loader/loader.conf".source = pkgs.writeText "loader.conf" ''
            timeout 0
            default ${entry}.conf
          '';
          "/loader/entries/${entry}.conf".source = pkgs.writeText "${entry}.conf" ''
            title ${entry}
            linux /EFI/${entry}/kernel
            initrd /EFI/${entry}/initrd
            options init=${build.toplevel}/init ${toString config.boot.kernelParams}
          '';
        };
        repartConfig = {
          Type = "esp";
          Format = "vfat";
          Label = "ESP";
          SizeMinBytes = "2G";
        };
      };
    };
  };

  # Boots the image twice (with a fake metadata service) and checks the
  # encrypted data partition, the host key and the name from the outside
  # (flake check nixbot-worker-boot).
  system.build.bootTest =
    pkgs.runCommand "nixbot-worker-boot-test"
      {
        nativeBuildInputs = [
          (pkgs.writeShellApplication {
            name = "boot-test";
            runtimeInputs = [
              pkgs.coreutils
              pkgs.gnugrep
              pkgs.gnused
              pkgs.jq
              pkgs.mtools
              pkgs.qemu_kvm
              pkgs.util-linux
            ];
            text = builtins.readFile ./scripts/boot-test.sh;
          })
        ];
        requiredSystemFeatures = [ "nixos-test" ];
      }
      ''
        boot-test ${config.image.repart.image}/${config.image.filePath} \
          ${pkgs.OVMF.fd}/FV/OVMF_CODE.fd ${pkgs.OVMF.fd}/FV/OVMF_VARS.fd "$out" \
          ${lib.getExe (
            pkgs.writeShellApplication {
              name = "metadata-responder";
              text = builtins.readFile ./scripts/metadata-responder.sh;
            }
          )}
      '';
}
