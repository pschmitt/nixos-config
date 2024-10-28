{ config, lib, ... }:
let
  secrets = [
    "geoip/accountID"
    "geoip/licenseKey"
    "parsedmarc/imap/password"
  ];
  grafanaHost = "grafana.${config.networking.hostName}.${config.custom.mainDomain}";
in
{
  sops.secrets = builtins.listToAttrs (
    map (secret: {
      name = secret;
      value = {
        sopsFile = config.custom.sopsFile;
      };
    }) secrets
  );

  services.geoipupdate = {
    enable = lib.mkForce false;
    settings = {
      # FIXME This is expected to be a signed int!
      AccountID = {
        _secrets = config.sops.secrets."geoip/accountID".path;
      };
      LicenseKey = {
        _secrets = config.sops.secrets."geoip/licenseKey".path;
      };
    };
  };

  services.grafana = {
    enable = true;
    settings = {
      server = {
        http_addr = "127.0.0.1";
        http_port = 47232;
        domain = grafanaHost;
      };
    };
  };

  services.nginx.virtualHosts."${grafanaHost}" = {
    enableACME = true;
    forceSSL = true;

    locations."/" = {
      proxyPass = "http://${toString config.services.grafana.settings.server.http_addr}:${toString config.services.grafana.settings.server.http_port}";
      proxyWebsockets = true;
      recommendedProxySettings = true;
    };
  };

  services.parsedmarc = {
    enable = true;
    settings = {
      imap = {
        host = "imap.gmail.com";
        port = 993;
        ssl = true;
        user = config.custom.email;
        password = {
          _secret = config.sops.secrets."parsedmarc/imap/password".path;
        };
      };
      mailbox = {
        watch = true;
        delete = false;
        test = true;
        reports_folder = "dmarc"; # gmail label
      };
      provision.geoip = lib.mkForce false;
    };
  };
}
