{ config, lib, ... }:
{
  config = lib.mkIf (!config.custom.cattle) {
    sops.secrets."mail/heimat-dev" = {
      sopsFile = config.custom.sopsFile;
    };
    sops.secrets."mail/gmail" = {
      sopsFile = config.custom.sopsFile;
    };

    programs.msmtp = {
      enable = !config.mailserver.enable;
      setSendmail = true;
      defaults = {
        auth = true;
        tls = true;
        tls_certcheck = true;
      };
      accounts = {
        default = {
          host = "mail.heimat.dev";
          port = 587;
          tls_starttls = true;
          tls_certcheck = false;
          from = "${config.networking.hostName}@heimat.dev";
          user = "${config.networking.hostName}@heimat.dev";
          passwordeval = "cat ${config.sops.secrets."mail/heimat-dev".path}";
        };
        gmail = {
          host = "smtp.gmail.com";
          port = 465;
          tls_starttls = false;
          from = "${config.networking.hostName}";
          user = "philipp@schmitt.co";
          passwordeval = "cat ${config.sops.secrets."mail/gmail".path}";
        };
      };
    };
  };
}
