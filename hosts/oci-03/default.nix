{
  imports = [
    ./disk-config.nix
    ./hardware-configuration.nix

    ../../common/server

    ../../services/restic
    ../../services/http.nix
    ../../services/mmonit.nix
    ../../services/parsedmarc.nix

    ./monit.nix
    ./restic.nix
  ];

  hardware.cattle = false;
  hardware.serverType = "oci";
  networking.hostName = "oci-03";
}
