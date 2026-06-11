{ lib, config, ... }:

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
    };
  };
}
