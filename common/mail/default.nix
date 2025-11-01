{
  inputs,
  config,
  lib,
  pkgs,
  ...
}:
let
  mylPkg = inputs.myl.packages.${stdenv.hostPlatform.system}.myl;
in
{
  config = lib.mkIf (!config.custom.cattle) {
    sops.secrets."mail/brkn-lol" = {
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

    environment.systemPackages = [
      mylPkg
      (pkgs.writeShellApplication {
        name = "mylbox";
        runtimeInputs = [
          mylPkg
          pkgs.util-linux
        ];
        text = ''
          myl --auto \
            --username "${config.networking.hostName}@${config.custom.mainDomain}" \
            --password-file "${config.sops.secrets."mail/brkn-lol".path}" \
            "$@"
        '';
      })
    ];
  };
}
