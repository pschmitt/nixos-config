{
  config,
  lib,
  pkgs,
  ...
}:
{
  config = lib.mkIf (!config.custom.cattle) {
    sops.secrets."mail/${config.custom.mainDomain}" = {
      sopsFile = config.custom.sopsFile;
      owner = config.custom.username;
    };
    sops.secrets."mail/gmail" = {
      sopsFile = config.custom.sopsFile;
      owner = config.custom.username;
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
          host = "mail.brkn.lol";
          port = 587;
          tls_starttls = true;
          tls_certcheck = false;
          from = "${config.networking.hostName}@brkn.lol";
          user = "${config.networking.hostName}@brkn.lol";
          passwordeval = "cat ${config.sops.secrets."mail/brkn-lol".path}";
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

    environment.systemPackages = with pkgs; [
      myl
      (pkgs.writeShellApplication {
        name = "myl-me";
        runtimeInputs = [
          pkgs.myl
          pkgs.util-linux
        ];
        text = ''
          myl_password=$(cat ${config.sops.secrets."mail/${config.custom.mainDomain}".path})
          if [ -z "$myl_password" ]; then
            echo "Failed to get myl password";
            exit 1;
          fi
          myl -u "${config.networking.HostName}"@${config.custom.mainDomain} -p "$myl_password" "$@"
        '';
      })
    ];
  };
}
