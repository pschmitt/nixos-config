{
  imports = [
    ../../modules/container-services.nix
    ../../services/audiobookshelf.nix
    ../../services/authelia-nginx-bypass.nix
    ../../services/http.nix
    ../../services/seerr.nix
    ../../services/tor.nix

    ./restic.nix
  ];

  services.containerServices.enable = true;
}
