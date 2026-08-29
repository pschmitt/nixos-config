{
  config,
  pkgs,
  ...
}:
let
  deviceGroups = import ../syncthing-device-groups.nix;
  personalDevices = deviceGroups.servers ++ deviceGroups.laptops ++ deviceGroups.phones;
  documentsDevices = personalDevices ++ deviceGroups.documentsPhones;
in
{
  imports = [
    ../syncthing.nix
    ../../modules/syncthing-tui.nix
  ];

  custom.syncthingTui = {
    enable = true;
    user = config.mainUser.username;
    homeDirectory = config.mainUser.homeDirectory;
    configXml = "${config.mainUser.homeDirectory}/.config/syncthing/config.xml";
  };

  # Folder ids must match the server's (hosts/rofl-10/syncthing.nix) for
  # Syncthing to pair them up automatically -- no manual "accept" step on
  # first connect. Paths default to ~/<label> on clients.
  custom.syncthing.folders = {
    documents = {
      label = "Documents";
      devices = documentsDevices;
    };
    music = {
      label = "Music";
      devices = personalDevices;
    };
    pictures = {
      label = "Pictures";
      devices = personalDevices;
    };
    backups = {
      label = "Backups";
      devices = personalDevices;
    };
  };

  home-manager.users.${config.mainUser.username} =
    { config, ... }:
    {
      home.packages = [
        pkgs.syncthingtray
        pkgs.syncthingtui
        pkgs.stui
      ];

      # --wait: the system tray isn't up yet this early in a session/login,
      # without it syncthingtray shows an error instead of waiting for it.
      xdg.desktopEntries.syncthingtray = {
        name = "Syncthing Tray";
        comment = "Tray application for Syncthing";
        exec = "${pkgs.syncthingtray}/bin/syncthingtray --wait";
        icon = "syncthingtray";
        terminal = false;
        categories = [
          "Network"
          "FileTransfer"
        ];
      };

      xdg.autostart.entries = [
        "${config.home.profileDirectory}/share/applications/syncthingtray.desktop"
      ];
    };
}
