{ lib, ... }:
{
  imports = [
    ./disk-config.nix
    ./hardware-configuration.nix
    ../../server
    ../../server/oci.nix

    ../../server/mmonit.nix
    ../../services/http.nix
    ../../services/parsedmarc.nix
    ../../common/restic

    ./monit.nix
    ./restic.nix
  ];

  networking.hostName = "oci-03";

  # FIXME nodejs_22 does not built currently on aarch64-linux (2025-09-07)
  programs.npm.enable = lib.mkForce false;
}
