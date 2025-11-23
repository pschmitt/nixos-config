{ lib, config, ... }:

{
  options = {
    custom = {
      username = lib.mkOption {
        type = lib.types.str;
        default = "pschmitt";
        description = "Main user's username.";
      };

      fullName = lib.mkOption {
        type = lib.types.str;
        default = "Philipp Schmitt";
        description = "Main user's full name.";
      };

      email = lib.mkOption {
        type = lib.types.str;
        default = "philipp@schmitt.co";
        description = "Main user email address.";
      };

      homeDirectory = lib.mkOption {
        type = lib.types.path;
        default = "/home/pschmitt";
        description = "Main user's home directory.";
      };

      sshKey = lib.mkOption {
        type = lib.types.path;
        default = "/home/pschmitt/.ssh/id_ed25519";
        description = "Main SSH key (used for age decryption)";
      };

      authorizedKeys = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default =
          let
            authorizedKeysContent = lib.strings.fileContents (
              builtins.fetchurl {
                url = "https://github.com/pschmitt.keys";
                sha256 = "sha256:1sr0r8g500zlalcb4bliwikwiqnrsng5ja2m83jshfxc44vi1i8i";
              }
            );
          in
          lib.splitString "\n" authorizedKeysContent;
        description = "Main SSH authorized keys file";
      };

      promptColor = lib.mkOption {
        type = lib.types.str;
        default = "white";
        description = "Main user's prompt color";
      };

      mainDomain = lib.mkOption {
        type = lib.types.str;
        default = "brkn.lol";
        description = "Main domain";
      };

      server = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Whether or not this is a server";
      };

      cattle = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Whether this is a cattle/throw-away server";
      };

      sopsFile = lib.mkOption {
        type = lib.types.path;
        default = ../hosts/${config.networking.hostName}/secrets.sops.yaml;
        description = "Host-specific SOPS configuration file";
      };

      netbirdSetupKey = lib.mkOption {
        type = lib.types.str;
        default = "default";
        description = "Netbird setup key name";
      };
    };

    home-manager.enabled = lib.mkEnableOption "home-manager for this host";
  };
}
