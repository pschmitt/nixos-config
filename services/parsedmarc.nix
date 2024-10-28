{ config, ... }:
{
  sops.secrets."parsedmarc/imap/hostname" = {
    sopsFile = config.custom.sopsFile;
  };
  sops.secrets."parsedmarc/imap/username" = {
    sopsFile = config.custom.sopsFile;
  };
  sops.secrets."parsedmarc/imap/password" = {
    sopsFile = config.custom.sopsFile;
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
    };
  };
}
