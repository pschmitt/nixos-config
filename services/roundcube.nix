{ config, pkgs, ... }:
let
  roundcubeHostName = "webmail.${config.custom.mainDomain}";
  mailHostName = "mail.${config.custom.mainDomain}";
in
{
  services.roundcube = {
    enable = true;
    configureNginx = true;
    hostName = roundcubeHostName;
    dicts = with pkgs.aspellDicts; [
      de
      en
      fr
    ];
    plugins = [ ];
    extraConfig = ''
      $config['smtp_host'] = "tls://${mailHostName}:587";
      $config['imap_host'] = "tls://${mailHostName}:143";
    '';
  };
}
