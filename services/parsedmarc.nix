{
  config,
  ...
}:
let
  grafanaHost = "grafana.${config.networking.hostName}.${config.domains.main}";
in
{
  sops.secrets = {
    "geoip/licenseKey" = config.sops.mkHostSecret {
    };
    "parsedmarc/imap/password" = config.sops.mkHostSecret {
    };
    "grafana/secretKey" = config.sops.mkHostSecret {
      owner = config.systemd.services.grafana.serviceConfig.User;
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
      provision.opensearch = true;

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
          user = config.mainUser.email.private;
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

  services.monit.checks = {
    grafana = {
      type = "host";
      address = "127.0.0.1";
      group = "services";
      restartUnit = "grafana.service";
      conditions = ''
        if failed
          port ${toString config.services.grafana.settings.server.http_port}
          protocol http
          request "/api/health"
          with timeout 15 seconds
          for 3 cycles
        then restart
        if 3 restarts within 15 cycles then alert
      '';
    };
  };
}
