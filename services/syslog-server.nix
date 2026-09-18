{ pkgs, ... }:
let
  logDir = "/srv/syslog-ng/data";
in
{
  services.syslog-ng = {
    enable = true;
    extraConfig = ''
      source s_local {
        internal();
      };

      source s_network {
        default-network-drivers();
      };

      destination d_local {
        file("${logDir}/messages");
        file(
          "${logDir}/$HOST.log"
          create-dirs(yes)
        );
      };

      log {
        source(s_local);
        source(s_network);
        destination(d_local);
      };
    '';
  };

  services.logrotate = {
    enable = true;
    settings.syslog-ng = {
      files = [
        "${logDir}/messages"
        "${logDir}/*.log"
      ];
      frequency = "daily";
      rotate = 7;
      size = "5M";
      sharedscripts = true;
      postrotate = "${pkgs.systemd}/bin/systemctl reload syslog-ng.service";
    };
  };

  systemd.tmpfiles.rules = [
    "d ${logDir} 0755 root root -"
  ];
}
