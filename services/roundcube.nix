{
  config,
  lib,
  pkgs,
  ...
}:
let
  roundcubeHostName = "webmail.${config.domains.main}";
  mailHostName = "mail.${config.domains.main}";
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

  services.monit.config = lib.mkAfter ''
    check host "roundcube" with address "127.0.0.1"
      group services
      depends on postgresql
      restart program = "${pkgs.systemd}/bin/systemctl restart phpfpm-roundcube.service"
      # TODO monitor the *INTERNAL* port/socket used by roundcube/phpfpm
      # https://github.com/NixOS/nixpkgs/blob/nixos-unstable/nixos/modules/services/mail/roundcube.nix
      if failed
        port 443
        protocol https
        with timeout 15 seconds
      then restart
      if 5 restarts within 10 cycles then alert
  '';
}
