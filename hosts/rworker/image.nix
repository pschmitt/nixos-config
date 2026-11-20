# Integration test for the shared worker image and this host's metadata setup.
{
  config,
  lib,
  pkgs,
  browserWorker ? false,
  ...
}:
{
  # Boots the image twice (with a fake metadata service) and checks the
  # encrypted data partition, the host key and the name from the outside
  # (flake check rworker-boot).
  system.build.bootTest =
    pkgs.runCommand "rworker-boot-test"
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
        NIXBOT_TEST_MEMORY_MIB = if browserWorker then "8192" else "3072";
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
