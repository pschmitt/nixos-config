{
  config,
  lib,
  pkgs,
  ...
}:
let
  grafanaHost = "grafana.${config.networking.hostName}.${config.domains.main}";
in
{
  sops.secrets = {
    "geoip/licenseKey" = {
      inherit (config.custom) sopsFile;
      owner = config.systemd.services.geoipupdate.serviceConfig.User;
    };
    "parsedmarc/imap/password" = {
      inherit (config.custom) sopsFile;
      owner = config.systemd.services.parsedmarc.serviceConfig.User;
    };
    "grafana/secretKey" = {
      inherit (config.custom) sopsFile;
      owner = config.systemd.services.grafana.serviceConfig.User;
      path = "${config.users.user.grafana.home}/secretKey";
    };
  };

  services = {
    geoipupdate = {
      enable = true;
      settings = {
        # FIXME This is expected to be a signed int and *not* a secret
        AccountID = 945501;
        LicenseKey = {
          _secret = config.sops.secrets."geoip/licenseKey".path;
        };
      };
    };

    grafana = {
      enable = true;
      settings = {
        server = {
          http_addr = "127.0.0.1";
          http_port = 47232;
          domain = grafanaHost;
          enable_gzip = true;
        };
        security.secret_key = "$__file{${config.sops.secrets."grafana/secretKey".path}}";
      };
    };

    nginx.virtualHosts."${grafanaHost}" = {
      enableACME = true;
      forceSSL = true;

      locations."/" = {
        proxyPass = "http://${toString config.services.grafana.settings.server.http_addr}:${toString config.services.grafana.settings.server.http_port}";
        proxyWebsockets = true;
        recommendedProxySettings = true;
      };
    };

    parsedmarc = {
      enable = true;
      provision.geoIp = true;
      provision.elasticsearch = true;

      # https://domainaware.github.io/parsedmarc/usage.html
      settings = {
        general = {
          silent = false;
          debug = true;
          save_aggregate = true;
          save_forensic = true;
          save_smtp_tls = true;
        };
        imap = {
          host = "imap.gmail.com";
          port = 993;
          ssl = true;
          user = config.mainUser.email;
          password = {
            _secret = config.sops.secrets."parsedmarc/imap/password".path;
          };
        };
        mailbox = {
          watch = true;
          delete = false;
          test = true; # do not move (archive) or delete any mail
          reports_folder = "dmarc"; # gmail label
          batch_size = 25;
        };
      };
    };
  };

  services.monit.config = lib.mkAfter ''
    check host "grafana" with address "127.0.0.1"
      group services
      restart program = "${pkgs.systemd}/bin/systemctl restart grafana.service"
      if failed
        port ${toString config.services.grafana.settings.server.http_port}
        protocol http
        request "/api/health"
        with timeout 15 seconds
      then restart
      if 5 restarts within 10 cycles then alert
  '';
}
