{ inputs, lib, config, nur, pkgs, ... }:
{
  home.packages = with pkgs; [
    bitwarden
    bitwarden-cli
  ];

  systemd.user.services.bitwarden-cli-sync = {
    Unit = {
      Description = "Bitwarden CLI Sync (bww)";
    };

    Service = {
      Type = "oneshot";
      Environment = "PATH=$PATH:${lib.makeBinPath [
        pkgs.zsh
        pkgs.bitwarden-cli
      ] }";
      ExecStart = "/home/pschmitt/bin/zhj 'bwp sync; gec::bwp sync'";
    };

    Install = {
      WantedBy = [ "default.target" ];
    };
  };

  systemd.user.timers.bitwarden-cli-sync = {
    Unit = {
      Description = "Bitwarden CLI Sync (bww)";
    };

    Timer = {
      OnCalendar = "*-*-* 00/2:00:00";
      Persistent = true;
    };

    Install = {
      WantedBy = [ "timers.target" ];
    };
  };
}
