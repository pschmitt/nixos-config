{
  config,
  lib,
  pkgs,
  ...
}:
{
  imports = [ ../syncthing.nix ];

  # stui ships no LICENSE file upstream (see pkgs/stui) -- explicitly opt in.
  nixpkgs.config.allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) [ "stui" ];

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
