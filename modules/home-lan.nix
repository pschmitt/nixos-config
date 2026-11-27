# Home LAN addressing, shared by NixOS and Home Manager. The values live in
# the private input; consumers must cope with them being null.
{ lib, ... }:
let
  inherit (lib) mkOption types;
  nullStr = mkOption {
    type = types.nullOr types.str;
    default = null;
  };
in
{
  options.networking.homeLan = {
    cidr = nullStr // {
      description = "Home LAN prefix (CIDR).";
    };
    gateway = nullStr // {
      description = "Home LAN router address.";
    };
    homeAssistant = nullStr // {
      description = "LAN address of the Home Assistant VM.";
    };
  };
}
