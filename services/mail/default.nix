{
  inputs,
  config,
  lib,
  pkgs,
  ...
}:
let
  mylPkg = inputs.myl.packages.${pkgs.stdenv.hostPlatform.system}.myl;
in
{
  config = lib.mkIf (!config.hardware.cattle) {
    sops.secrets."mail/brkn-lol" = {
      inherit (config.custom) sopsFile;
      owner = config.mainUser.username;
    };
    sops.secrets."mail/gmail" = {
      inherit (config.custom) sopsFile;
      owner = config.mainUser.username;
    };

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
            --username "${config.networking.hostName}@${config.domains.main}" \
            --password-file "${config.sops.secrets."mail/brkn-lol".path}" \
            "$@"
        '';
      })
    ];
  };
}
