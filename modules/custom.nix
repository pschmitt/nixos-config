{ lib, config, ... }:

{
  options = {
    custom.username = lib.mkOption {
      type = lib.types.str;
      default = "pschmitt";
      description = "Main user's username.";
    };

    custom.fullName = lib.mkOption {
      type = lib.types.str;
      default = "Philipp Schmitt";
      description = "Main user's full name.";
    };

    custom.email = lib.mkOption {
      type = lib.types.str;
      default = "philipp@schmitt.co";
      description = "Main user email address.";
    };

    custom.homeDirectory = lib.mkOption {
      type = lib.types.path;
      default = "/home/pschmitt";
      description = "Main user's home directory.";
    };

    custom.sshKey = lib.mkOption {
      type = lib.types.path;
      default = "/home/pschmitt/.ssh/id_ed25519";
      description = "Main SSH key (used for age decryption)";
    };

    custom.authorizedKeys = lib.mkOption {
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

    custom.promptColor = lib.mkOption {
      type = lib.types.str;
      default = "white";
      description = "Main user's prompt color";
    };

    custom.mainDomain = lib.mkOption {
      type = lib.types.str;
      default = "brkn.lol";
      description = "Main domain";
    };

    custom.server = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Whether or not this is a server";
    };

    custom.useBIOS = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Use BIOS instead of UEFI";
    };

    custom.raspberryPi = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Whether this is a Raspberry Pi";
    };

    custom.kvmGuest = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether this is cloud-based server";
    };

    custom.cattle = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether this is a cattle/throw-away server";
    };

    custom.sopsFile = lib.mkOption {
      type = lib.types.path;
      default = ../hosts/${config.networking.hostName}/secrets.sops.yaml;
      description = "Host-specific SOPS configuration file";
    };

    custom.netbirdSetupKey = lib.mkOption {
      type = lib.types.str;
      default = "default";
      description = "Netbird setup key name";
    };
  };
}
