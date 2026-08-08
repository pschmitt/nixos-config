{ lib, ... }:

{
  options = {
    custom = {
      netbirdSetupKey = lib.mkOption {
        type = lib.types.str;
        default = "default";
        description = "Netbird setup key name";
      };

      promptColor = lib.mkOption {
        type = lib.types.str;
        default = "white";
        description = "Main user's prompt color";
      };

      httpStatic = {
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
    };
  };
}
