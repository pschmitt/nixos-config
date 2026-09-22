{ config, ... }:
{
  home-manager.users.${config.mainUser.username} = { config, ... }: {
    host.extraAutostartEntries = [
      "${config.home.profileDirectory}/share/applications/obs-studio-autostart.desktop"
    ];
    services.go-hass-agent.enableWorkCommands = true;
  };
}
