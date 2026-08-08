{
  lib,
  pkgs,
  ...
}:
let
  traefikConfig = (pkgs.formats.yaml { }).generate "oci-01-mail-traefik.yaml" {
    http = {
      routers = {
        stalwart = {
          entryPoints = [ "https" ];
          rule = "Host(`stalwart.brkn.lol`) || Host(`autoconfig.brkn.lol`) || Host(`autodiscover.brkn.lol`) || Host(`autoconfig.pschmitt.dev`) || Host(`autodiscover.pschmitt.dev`)";
          service = "stalwart";
          tls.certResolver = "le";
        };
        roundcube = {
          entryPoints = [ "https" ];
          rule = "Host(`mail.brkn.lol`) || Host(`mail.pschmitt.dev`)";
          service = "roundcube";
          tls.certResolver = "le";
        };
        "autodiscover-schmitt-co" = {
          entryPoints = [ "https" ];
          priority = 1000;
          rule = "Host(`autoconfig.schmitt.co`) || Host(`autodiscover.schmitt.co`)";
          service = "autodiscover-schmitt-co";
          tls = {
            certResolver = "le";
            domains = [
              {
                main = "autoconfig.schmitt.co";
                sans = [ "autodiscover.schmitt.co" ];
              }
            ];
          };
        };
      };
      services = {
        stalwart.loadBalancer.servers = [ { url = "http://host.docker.internal:8080"; } ];
        roundcube.loadBalancer.servers = [ { url = "http://host.docker.internal:2020"; } ];
        "autodiscover-schmitt-co".loadBalancer.servers = [ { url = "http://host.docker.internal:2020"; } ];
      };
    };
  };
in
{
  systemd.services.oci-01-mail-traefik-config = {
    description = "Install the Nix-managed OCI-01 mail routes for Traefik";
    wantedBy = [ "multi-user.target" ];
    wants = [ "mnt-data.mount" ];
    after = [ "mnt-data.mount" ];
    before = [ "legacy-compose-traefik.service" ];
    unitConfig.RequiresMountsFor = [ "/srv/traefik/config/dynamic" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${pkgs.coreutils}/bin/install -Dm0644 ${traefikConfig} /srv/traefik/config/dynamic/mail.yaml";
    };
  };
}
