{ config, ... }:
{
  sops.secrets."geoip/accountID" = {
    sopsFile = config.custom.sopsFile;
  };
  sops.secrets."geoip/licenseKey" = {
    sopsFile = config.custom.sopsFile;
  };
  sops.secrets."parsedmarc/imap/hostname" = {
    sopsFile = config.custom.sopsFile;
  };
  sops.secrets."parsedmarc/imap/username" = {
    sopsFile = config.custom.sopsFile;
  };
  sops.secrets."parsedmarc/imap/password" = {
    sopsFile = config.custom.sopsFile;
  };

  services.geoipupdate = {
    enable = true;
    settings = {
      AccountID = {
        _secrets = config.sops.secrets."geoip/accountID".path;
      };
      LicenseKey = {
        _secrets = config.sops.secrets."geoip/licenseKey".path;
      };
    };
  };

  services.parsedmarc = {
    enable = true;
    settings = {
      imap = {
        host = {
          _secret = config.sops.secrets."parsedmarc/imap/hostname".path;
        };
        port = 993;
        ssl = true;
        user = {
          _secret = config.sops.secrets."parsedmarc/imap/username".path;
        };
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
      # provision.grafana.dashboard = true;
      provision.geoip = config.geoipupdate.enable;
    };
  };
}
