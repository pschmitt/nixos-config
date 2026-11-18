{ lib, ... }:
{
  options.fullNix.upgradeCache = lib.mkOption {
    type = lib.types.nullOr (
      lib.types.submodule {
        options = {
          store = lib.mkOption { type = lib.types.str; };
          pin_reader = lib.mkOption { type = lib.types.str; };
          public_keys = lib.mkOption { type = lib.types.listOf lib.types.str; };
          credentials_file = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
          };
        };
      }
    );
    default = null;
    description = "Signed binary cache and host-specific pin reader for nixpp upgrade.";
  };
}
