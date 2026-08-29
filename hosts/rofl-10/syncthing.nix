{
  config,
  pkgs,
  ...
}:
let
  # syncthingtui auto-discovers its API key/address from a local user's own
  # config.xml, but rofl-10's Syncthing runs as the system "syncthing" user
  # -- not reachable that way when pschmitt runs it over SSH. Reuse the
  # api_key custom.syncthingTui below already resolves into
  # ~/.config/stui/config.yaml instead of re-deriving it separately.
  syncthingtuiWrapped = pkgs.writeShellScriptBin "syncthingtui" ''
    set -euo pipefail
    api_key=$(${pkgs.gnused}/bin/sed -n 's/^api_key: "\(.*\)"$/\1/p' ~/.config/stui/config.yaml)
    exec ${pkgs.syncthingtui}/bin/syncthingtui -address 127.0.0.1:8384 -api-key "$api_key" "$@"
  '';

  deviceGroups = import ../../profiles/syncthing-device-groups.nix;
  personalDevices = deviceGroups.servers ++ deviceGroups.laptops ++ deviceGroups.phones;
in
{
  imports = [
    ../../profiles/syncthing.nix
    ../../modules/syncthing-tui.nix
  ];

  custom.syncthingTui = {
    enable = true;
    user = config.mainUser.username;
    homeDirectory = config.mainUser.homeDirectory;
    configXml = "/var/lib/syncthing/.config/syncthing/config.xml";
  };

  environment.systemPackages = [
    syncthingtuiWrapped
    pkgs.stui
  ];

  custom.syncthing = {
    folders = {
      documents = {
        label = "Documents";
        dir = "/mnt/data/srv/syncthing/documents";
        devices = personalDevices;
      };
      music = {
        label = "Music";
        dir = "/mnt/data/srv/syncthing/music";
        devices = personalDevices;
      };
      pictures = {
        label = "Pictures";
        dir = "/mnt/data/srv/syncthing/pictures";
        devices = personalDevices;
      };
      backups = {
        label = "Backups";
        dir = "/mnt/data/srv/syncthing/backups";
        devices = personalDevices;
      };
    };
  };

  services.nginx.virtualHosts."sync.${config.domains.main}" = {
    enableACME = true;
    # FIXME https://github.com/NixOS/nixpkgs/issues/210807
    acmeRoot = null;
    forceSSL = true;
    basicAuthFile = config.sops.secrets."htpasswd".path;

    locations."/" = {
      proxyPass = "http://127.0.0.1:8384";
      proxyWebsockets = true;
      recommendedProxySettings = true;
    };
  };
}
