{
  imports = [
    ./disk-config.nix
    ./hardware-configuration.nix

    ../../common/server
    ../../common/server/oci.nix

    ../../services/restic
    ../../services/http.nix
    ../../services/mmonit.nix
    ../../services/parsedmarc.nix

    ./monit.nix
    ./restic.nix
  ];

  hardware.cattle = false;
  networking.hostName = "oci-03";
}
