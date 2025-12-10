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

      sopsFile = lib.mkOption {
        type = lib.types.path;
        default = ../hosts/${config.networking.hostName}/secrets.sops.yaml;
        description = "Host-specific SOPS configuration file";
      };
    };

    home-manager.enabled = lib.mkEnableOption "home-manager for this host";
  };
}
