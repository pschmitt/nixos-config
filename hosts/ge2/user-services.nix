{ config, ... }:
{
  services.ppd-react = {
    stopUserSystemdUnitsOnPowerSaver = [ "obs-studio-autostart.service" ];
    resumeUserSystemdUnitsOnPowerSaverExit = [ "obs-studio-autostart.service" ];
  };

  home-manager.users.${config.mainUser.username} = { config, ... }: {
    systemd.user.services.obs-studio-autostart = {
      Unit = {
        Description = "Start OBS Studio on workdays";
        PartOf = [ "graphical-session.target" ];
        After = [ "graphical-session.target" ];
      };
      Service.ExecStart = "${config.home.profileDirectory}/bin/obs-hyprland-autostart --workdays-only";
      Install.WantedBy = [ "graphical-session.target" ];
    };

    services.go-hass-agent.enableWorkCommands = true;
  };
}
