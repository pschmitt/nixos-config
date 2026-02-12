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
    # Allow non-NixOS/external devices to specify their own addresses in JSON.
    # If omitted, default to the VPN hostname + dynamic discovery.
    addresses = device.addresses or (mkAddresses host);
    introducer = device.introducer or false;
  }) devices;
}
