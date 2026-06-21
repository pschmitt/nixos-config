# arr — media acquisition and streaming stack: downloaders, Jellyfin, Jellyseerr and Tdarr.
{ ... }:
{
  imports = [
    ../services/arr
    ../services/authelia-nginx-bypass.nix
    ../services/jellyfin.nix
    ../services/seerr.nix
    ../services/tdarr-server.nix
  ];
}
