{
  imports = [
    ./disk-config.nix
    ./hardware-configuration.nix

    ../../profiles/server

    ../../services/restic
    ../../services/http.nix
    ../../services/mmonit.nix
    ../../services/parsedmarc.nix

    ./monit.nix
    ./restic.nix
  ];

  hardware = {
    cattle = false;
    serverType = "oci";
  };
  networking.hostName = "oci-03";
}
