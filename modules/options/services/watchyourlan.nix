{ lib, ... }:
{
  options.services.watchyourlan.interfaces = lib.mkOption {
    type = lib.types.listOf lib.types.str;
    default = [ "hass-br0" ];
    description = "Interfaces WatchYourLAN should scan for network discovery.";
  };
}
