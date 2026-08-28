{ config, pkgs, ... }:
{
  imports = [ ../syncthing.nix ];

  # Folder ids must match the server's (hosts/rofl-10/syncthing.nix) for
  # Syncthing to pair them up automatically -- no manual "accept" step on
  # first connect. Paths default to ~/<label> on clients.
  custom.syncthing.folders = {
    documents = {
      label = "Documents";
    };
    music = {
      label = "Music";
    };
    pictures = {
      label = "Pictures";
    };
    backups = {
      label = "Backups";
    };
  };

  home-manager.users.${config.mainUser.username} = {
    home.packages = [ pkgs.syncthingtray ];
    xdg.autostart.entries = [
      "${pkgs.syncthingtray}/share/applications/syncthingtray.desktop"
    ];
  };
}
