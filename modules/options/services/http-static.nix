{ lib, ... }:
{
  options.services.http-static = {
    enableDefaultSites = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable the default static sites provided by services/http-static.nix";
    };

    extraVirtualHosts = lib.mkOption {
      type = lib.types.attrs;
      default = { };
      description = "Additional Nginx virtual hosts provided by services/http-static.nix";
    };
  };
}
