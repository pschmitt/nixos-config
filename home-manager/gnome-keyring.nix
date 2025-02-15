{ config, ... }:
{
  systemd.user.services.gnome-keyring-auto-unlock = {
    Unit = {
      Description = "Auto-unlock GNOME keyring";
    };

    Service = {
      Type = "oneshot";
      ExecStart = "${config.home.homeDirectory}/bin/zhj gnome-keyring::auto-unlock --verbose --no-callback";
    };
  };

  # systemd.user.timers.gnome-keyring-auto-unlock = {
  #   Unit = {
  #     Description = "Auto-unlock GNOME keyring every 5 minutes";
  #   };
  #
  #   Timer = {
  #     OnCalendar = "*:0/5"; # every 5 min
  #   };
  #
  #   Install = {
  #     WantedBy = [ "timers.target" ];
  #   };
  # };
}
