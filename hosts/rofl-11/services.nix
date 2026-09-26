{
  imports = [
    ../../modules/container-services.nix
    ../../services/audiobookshelf.nix
    ../../services/authelia-nginx-bypass.nix
    ../../services/http.nix
    ../../services/jellyfin.nix
    ../../services/seerr.nix
    ../../services/tdarr-server.nix
    ../../services/tor.nix

    ./monit.nix
    ./restic.nix
  ];

  services.containerServices.enable = true;
}
