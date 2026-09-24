# syncthing — shared interactive-server Syncthing configuration.
{ config, ... }:
{
  imports = [ ../../../../services/syncthing/web.nix ];

  home-manager.users.${config.mainUser.username}.imports = [ ./syncthing-home.nix ];

  # Home Manager's syncthing service runs as mainUser and expects to own
  # these folders (declared in ./syncthing-home.nix). Enforce that
  # ownership recursively at system activation so a root-owned tree left
  # behind by e.g. a migration rsync run as root doesn't wedge
  # syncthing-init.service in a permission-denied retry loop.
  systemd.tmpfiles.rules =
    map
      (
        label:
        "Z ${config.mainUser.homeDirectory}/${label} - ${config.mainUser.username} ${config.mainUser.username} -"
      )
      [
        "Documents"
        "Music"
        "Pictures"
        "Backups"
      ];
}
