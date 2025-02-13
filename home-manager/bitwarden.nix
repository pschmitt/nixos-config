{ lib, pkgs, ... }:
{
  home.packages = with pkgs; [
    bitwarden
    master.bitwarden-cli
    rbw
  ];

  systemd.user.services.bitwarden-cli-sync = {
    Unit = {
      Description = "Bitwarden CLI Sync (bww)";
    };

    Service = {
      Type = "oneshot";
      Environment = "PATH=$PATH:${
        lib.makeBinPath [
          pkgs.bash
          pkgs.zsh
          pkgs.master.bitwarden-cli
        ]
      }";
      ExecStart = "/home/pschmitt/bin/zhj 'bwp sync --force; gec::bwp sync --force'";
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
