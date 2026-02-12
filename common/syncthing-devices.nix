{
  config,
  lib,
  ...
}:
let
  devices = builtins.fromJSON (builtins.readFile ./syncthing-devices.json);
  vpnDomain = config.domains.vpn;
  mkAddresses = host: [
    "tcp://${host}.${vpnDomain}"
    "dynamic"
  ];
in
{
  custom.syncthing.devices = lib.mapAttrs (host: device: {
    inherit (device) id;
    addresses = mkAddresses host;
    introducer = device.introducer or false;
  }) devices;
}
