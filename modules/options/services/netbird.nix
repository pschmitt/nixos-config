{ lib, ... }:
{
  options.services.netbird.setupKeyName = lib.mkOption {
    type = lib.types.str;
    default = "default";
    description = "SOPS setup-key name used by the NetBird network profile.";
  };
}
