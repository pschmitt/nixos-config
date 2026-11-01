# syncthing — shared interactive-server Syncthing configuration.
{ config, ... }:
{
  imports = [ ../../../../services/syncthing/web.nix ];

  home-manager.users.${config.mainUser.username}.imports = [ ./syncthing-home.nix ];

  # Syncthing runs as a Home Manager user service, which cannot open the host
  # firewall itself: open the default sync and local discovery ports here
  # (what services.syncthing.openDefaultPorts does for the system service).
  networking.firewall = {
    allowedTCPPorts = [ 22000 ];
    allowedUDPPorts = [
      22000
      21027
    ];
  };

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
