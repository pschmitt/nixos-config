{
  inputs,
  lib,
  pkgs,
  ...
}:
let
  listen = [
    {
      addr = "0.0.0.0";
      port = 2020;
    }
  ];
  pschmittDevPackage = inputs.pschmitt-dev.packages.${pkgs.stdenv.hostPlatform.system}.default;
in
{
  imports = [
    ../../services/http.nix
    ../../services/http-static.nix
  ];

  custom.httpStatic = {
    enableDefaultSites = false;
    extraVirtualHosts = {
      "pschmitt.dev" = {
        inherit listen;
        locations = {
          "/" = {
            root = pschmittDevPackage;
          };
          "= /gh".return = "301 https://github.com/pschmitt";
          "= /github".return = "301 https://github.com/pschmitt";
          "= /gpg".return = "301 https://keybase.io/pschmitt/key.asc";
          "= /mastodon".return = "301 https://fosstodon.org/@pschmitt";
          "= /n".return = "301 https://go.nordvpn.net/aff_c?offer_id=15&aff_id=80335&url_id=902";
          "= /nordvpn".return = "301 https://go.nordvpn.net/aff_c?offer_id=15&aff_id=80335&url_id=902";
          "= /resume".return = "302 https://p.schmi.tt/resume-pschmitt-2024.pdf";
          "= /cv".return = "302 https://p.schmi.tt/resume-pschmitt-2024.pdf";
          "= /lebenslauf".return = "302 https://p.schmi.tt/resume-pschmitt-2024.pdf";
          "= /tldr".return = "302 https://p.schmi.tt/resume-pschmitt-2024-tldr.pdf";
          "= /resume.json".return =
            "301 https://gist.githubusercontent.com/pschmitt/0ab646d4a39b16393db354c6e1082305/raw";
          "= /ssh".return = "301 https://github.com/pschmitt.keys";
          "= /twitter".return = "301 https://twitter.com/pppschmitt";
        };
      };

      "p.schmi.tt" = {
        inherit listen;
        locations."/" = {
          root = pschmittDevPackage;
        };
      };

      "philipp.schmi.tt" = {
        inherit listen;
        locations."/" = {
          root = pschmittDevPackage;
        };
      };

      "github.pschmitt.dev" = {
        inherit listen;
        locations."/".return = "301 https://github.com/pschmitt";
      };

      "gh.pschmitt.dev" = {
        inherit listen;
        locations."/".return = "301 https://github.com/pschmitt";
      };

      "schmitt.co" = {
        inherit listen;
        locations."/" = {
          root = "/srv/caddy/data/schmitt.co";
          extraConfig = "autoindex on;";
        };
      };
    };
  };

  services.nginx.defaultListen = listen;

  # The public Nginx vhosts proxy to this local backend during the migration.
  networking.firewall.allowedTCPPorts = [ 2020 ];

  systemd.services.nginx = {
    requires = [ "mnt-data.mount" ];
    after = [ "mnt-data.mount" ];
    unitConfig.RequiresMountsFor = [ "/srv/caddy/data/schmitt.co" ];
  };

  services.monit.config = lib.mkAfter ''
    check host "oci-01-http-static" with address "127.0.0.1"
      group nginx
      group services
      if failed
        port 8443
        protocol https
        with hostheader "pschmitt.dev"
        request "/"
        with timeout 10 seconds
      for 3 cycles
      then alert
  '';

}
