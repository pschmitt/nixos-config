{ config, ... }: {
  age.secrets.msmtp-password-heimat-dev.file = ../../secrets/${config.networking.hostName}/msmtp-password-heimat-dev.age;
  age.secrets.msmtp-password-gmail.file = ../../secrets/${config.networking.hostName}/msmtp-password-gmail.age;

  programs.msmtp = {
    enable = true;
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
        passwordeval = "cat ${config.age.secrets.msmtp-password-heimat-dev.path}";
      };
      gmail = {
        host = "smtp.gmail.com";
        port = 465;
        tls_starttls = false;
        from = "${config.networking.hostName}";
        user = "philipp@schmitt.co";
        passwordeval = "cat ${config.age.secrets.msmtp-password-gmail.path}";
      };
    };
  };
}
