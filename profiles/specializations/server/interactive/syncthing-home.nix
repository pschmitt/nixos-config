{
  config,
  hostname,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  syncthingDevices = builtins.fromJSON (
    builtins.readFile (inputs.nixos-config-private.outPath + "/data/syncthing/devices.json")
  );
  otherDevices = lib.filterAttrs (name: _: name != hostname) syncthingDevices;
  vpnDomain = config.domains.vpn;
  mkAddresses = host: [
    "tcp://${host}.${vpnDomain}"
    "dynamic"
  ];

  deviceGroups = import (inputs.nixos-config-private.outPath + "/data/syncthing/device-groups.nix");
  personalDevices = lib.filter (d: otherDevices ? ${d}) (
    deviceGroups.servers ++ deviceGroups.laptops ++ deviceGroups.phones
  );
  documentsDevices = lib.filter (d: otherDevices ? ${d}) (
    deviceGroups.servers ++ deviceGroups.laptops ++ deviceGroups.phones ++ deviceGroups.documentsPhones
  );

  mkFolder = name: label: devices: {
    id = name;
    inherit label;
    path = "${config.home.homeDirectory}/${label}";
    inherit devices;
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
  imports = [ ../../../../modules/syncthing/home-manager/tui.nix ];

  home.packages = [
    pkgs.syncthingtui
    pkgs.stui
  ];

  services.syncthing = {
    enable = true;
    # ~/.local/state/syncthing is also where the previous Fedora (dnf)
    # package kept its config -- the existing cert.pem/key.pem there are
    # picked up as-is, so this device keeps the id already registered in
    # the private Syncthing device registry instead of re-pairing as new.
    overrideDevices = true;
    overrideFolders = true;

    settings = {
      devices = lib.mapAttrs (host: device: {
        inherit (device) id;
        addresses = device.addresses or (mkAddresses host);
        introducer = device.introducer or false;
      }) otherDevices;

      folders = {
        documents = mkFolder "documents" "Documents" documentsDevices;
        music = mkFolder "music" "Music" personalDevices;
        pictures = mkFolder "pictures" "Pictures" personalDevices;
        backups = mkFolder "backups" "Backups" personalDevices;
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
