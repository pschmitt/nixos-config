{ lib, ... }:
{
  imports = [
    ./disk-config.nix
    ./hardware-configuration.nix

    ../../server
    ../../server/oci.nix

    ../../common/restic
    ../../services/http.nix
    ../../services/mmonit.nix
    ../../services/parsedmarc.nix

    ./monit.nix
    ./restic.nix
  ];

  custom.cattle = false;
  networking.hostName = "oci-03";

  # FIXME nodejs_22 does not built currently on aarch64-linux (2025-09-07)
  programs.npm.enable = lib.mkForce false;
}
