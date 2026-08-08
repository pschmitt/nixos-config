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
  traefikConfig = pkgs.writeText "oci-01-http-static-traefik.yaml" ''
    http:
      routers:
        oci-01-http-static:
          entryPoints:
            - https
          rule: "Host(`pschmitt.dev`) || Host(`p.schmi.tt`) || Host(`philipp.schmi.tt`) || Host(`github.pschmitt.dev`) || Host(`gh.pschmitt.dev`) || Host(`schmitt.co`)"
          service: oci-01-http-static
          tls:
            certResolver: le

      services:
        oci-01-http-static:
          loadBalancer:
            servers:
              - url: "http://host.docker.internal:2020"
  '';
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
        port 2020
        protocol http
        request "/"
        with timeout 10 seconds
      for 3 cycles
      then alert
  '';

  systemd.services.oci-01-http-static-traefik-config = {
    description = "Install the Nix-managed OCI-01 static-site route for Traefik";
    wantedBy = [ "multi-user.target" ];
    wants = [ "mnt-data.mount" ];
    after = [ "mnt-data.mount" ];
    before = [ "legacy-compose-traefik.service" ];
    unitConfig.RequiresMountsFor = [ "/srv/traefik/config/dynamic" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${pkgs.coreutils}/bin/install -Dm0644 ${traefikConfig} /srv/traefik/config/dynamic/http-static.yaml";
    };
  };
}
