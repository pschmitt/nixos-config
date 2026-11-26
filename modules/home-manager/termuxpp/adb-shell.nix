{
  config,
  lib,
  ...
}:
let
  cfg = config.nixpp.adbShell;
in
{
  options.nixpp.adbShell.allowedSsidsFile = lib.mkOption {
    type = lib.types.nullOr lib.types.str;
    default = null;
    example = "/run/user/secrets/wifi/home-ssids";
    description = ''
      Like `allowedSsids`, but read at activation from this file, one Wi-Fi
      name per line: a secret path, so the names stay out of the Nix store.
      An unreadable file allows no network.
    '';
  };

  options.nixpp.adbShell.allowedSsids = lib.mkOption {
    type = lib.types.listOf lib.types.str;
    default = [ ];
    example = [ "home-lan" ];
    description = ''
      Exact Wi-Fi names on which the TermuxPP ADB shell listener may run
      (`adb-shell-allowed-ssids`). Empty (and no allowedSsidsFile) allows any
      network. Keep the real names in the private configuration.
    '';
  };

  # properties.nix writes the list into config.yaml.
  config = {
    assertions = [
      {
        assertion = cfg.allowedSsids == [ ] || cfg.allowedSsidsFile == null;
        message = "nixpp.adbShell: set allowedSsids or allowedSsidsFile, not both";
      }
    ];
  };
}
