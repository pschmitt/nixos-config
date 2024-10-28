{ config, lib, ... }:
let
  secrets = [
    "geoip/accountID"
    "geoip/licenseKey"
    "parsedmarc/imap/hostname"
    "parsedmarc/imap/username"
    "parsedmarc/imap/password"
  ];
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
      provision.geoip = lib.mkForce false;
    };
  };
}
