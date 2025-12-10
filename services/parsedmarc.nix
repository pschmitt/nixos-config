{ config, ... }:
let
  secrets = [
    "geoip/licenseKey"
    "parsedmarc/imap/password"
  ];
  grafanaHost = "grafana.${config.networking.hostName}.${config.domains.main}";
in
{
  sops.secrets = builtins.listToAttrs (
    map (secret: {
      name = secret;
      value = {
        inherit (config.custom) sopsFile;
      };
    }) secrets
  );

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
}
