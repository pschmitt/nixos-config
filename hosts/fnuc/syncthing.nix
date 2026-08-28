{ config, lib, ... }:
let
  syncthingDevices = builtins.fromJSON (builtins.readFile ../../profiles/syncthing-devices.json);
  otherDevices = lib.filterAttrs (name: _: name != "fnuc") syncthingDevices;
  vpnDomain = config.domains.vpn;
  mkAddresses = host: [
    "tcp://${host}.${vpnDomain}"
    "dynamic"
  ];

  mkFolder = name: label: {
    id = name;
    inherit label;
    path = "${config.home.homeDirectory}/${label}";
    devices = lib.attrNames otherDevices;
    type = "sendreceive";
    ignorePerms = false;
    ignorePatterns = [
      ".sync_*.db*"
      ".sync"
      ".sync-conflict-*"
      ".nextcloudsync.log"
    ];
  };
in
{
  imports = [ ../../modules/home-manager/syncthing-tui.nix ];

  services.syncthing = {
    enable = true;
    # ~/.local/state/syncthing is also where the previous Fedora (dnf)
    # package kept its config -- the existing cert.pem/key.pem there are
    # picked up as-is, so this device keeps the id already registered in
    # ../../profiles/syncthing-devices.json instead of re-pairing as new.
    overrideDevices = true;
    overrideFolders = true;

    settings = {
      devices = lib.mapAttrs (host: device: {
        inherit (device) id;
        addresses = device.addresses or (mkAddresses host);
        introducer = device.introducer or false;
      }) otherDevices;

      folders = {
        documents = mkFolder "documents" "Documents";
        music = mkFolder "music" "Music";
        pictures = mkFolder "pictures" "Pictures";
        backups = mkFolder "backups" "Backups";
      };

      gui = {
        user = "";
        password = "";
      };

      options = {
        urAccepted = -1;
        relaysEnabled = true;
      };
    };
  };
}
