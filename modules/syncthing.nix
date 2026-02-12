{ config, lib, ... }:

{
  options.custom.syncthing = {
    enable = lib.mkEnableOption "syncthing with declarative devices";

    server = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Whether this is the server instance";
    };

    devices = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            id = lib.mkOption {
              type = lib.types.str;
              default = "";
              description = "Syncthing device ID";
            };
            addresses = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [ "dynamic" ];
              description = "Addresses for this device";
            };
            introducer = lib.mkOption {
              type = lib.types.bool;
              default = false;
              description = "Whether this device is an introducer";
            };
          };
        }
      );
      default = { };
      description = "All syncthing devices in the network";
    };
  };

  config =
    let
      cfg = config.custom.syncthing;
      currentHost = config.networking.hostName;
      otherDevices = lib.filterAttrs (name: _: name != currentHost) cfg.devices;
      syncthingUser = if cfg.server then "syncthing" else config.mainUser.username;
    in
    lib.mkIf cfg.enable {
      services.syncthing = {
        enable = true;
        openDefaultPorts = true;
        user = syncthingUser;
        group = syncthingUser;
        dataDir = if cfg.server then "/var/lib/syncthing" else config.mainUser.homeDirectory;
        configDir =
          if cfg.server then
            "/var/lib/syncthing/.config/syncthing"
          else
            "${config.mainUser.homeDirectory}/.config/syncthing";
        overrideDevices = true;
        overrideFolders = true;

        settings = {
          devices = lib.mapAttrs' (
            name: device:
            lib.nameValuePair name {
              inherit (device) id addresses;
              introducer = device.introducer or false;
            }
          ) otherDevices;

          folders.documents = {
            id = "documents";
            label = "Documents";
            path =
              if cfg.server then "/var/lib/syncthing/documents" else "${config.mainUser.homeDirectory}/Documents";
            devices = lib.attrNames otherDevices;
            # Server should not be authoritative; it’s the backup/receiver by default.
            type = if cfg.server then "receiveonly" else "sendreceive";
            ignorePerms = false;
          };

          gui = {
            # Authentication is handled by the reverse proxy on the server.
            user = "";
            password = "";
          }
          // lib.optionalAttrs cfg.server {
            address = "127.0.0.1:8384";
            # Required when accessing the GUI via reverse proxy with a different Host header.
            insecureSkipHostcheck = true;
          };

          options = {
            urAccepted = -1;
            relaysEnabled = true;
          };
        };
      };

      systemd.tmpfiles.rules = lib.optionals cfg.server [
        "d /var/lib/syncthing/documents 0755 syncthing syncthing -"
      ];
    };
}
