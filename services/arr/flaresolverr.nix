{ pkgs, ... }:
let
  port = 8191;
in
{
  arr.services.flaresolverr = {
    inherit port;
    # No public vhost; reached locally via fakeHosts only.
    monit.request = "/health";
  };

  services.flaresolverr = {
    enable = true;
    package = pkgs.flaresolverr;
    inherit port;
    openFirewall = false;
  };
}
