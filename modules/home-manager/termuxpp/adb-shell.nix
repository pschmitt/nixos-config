{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.fullNix.adbShell;
  properties = "${config.xdg.configHome}/termuxpp/termuxpp.properties";
  # Merge one key and leave every other property, including GUI edits, alone.
  setAllowedSsids =
    pkgs.writers.writePython3 "termuxpp-adb-shell-allowed-ssids"
      {
        libraries = [ pkgs.python3Packages.javaproperties ];
      }
      ''
        import os
        import sys

        import javaproperties

        path, value = sys.argv[1], sys.argv[2]
        if value == "--file":
            # One Wi-Fi name per line (a secret), so the names stay out of
            # the Nix store. Leave the property alone when it is unreadable.
            try:
                with open(sys.argv[3], encoding="utf-8") as source:
                    names = [line.strip() for line in source]
            except OSError as error:
                print(f"adb-shell allow-list: {error}; property unchanged",
                      file=sys.stderr)
                sys.exit(0)
            value = ",".join(name for name in names if name)
        props = {}
        if os.path.exists(path):
            with open(path, encoding="utf-8") as source:
                props = javaproperties.load(source)
        if props.get("adb-shell-allowed-ssids") == value:
            sys.exit(0)
        props["adb-shell-allowed-ssids"] = value
        os.makedirs(os.path.dirname(path), exist_ok=True)
        temporary = path + ".tmp"
        with open(temporary, "w", encoding="utf-8") as target:
            javaproperties.dump(props, target)
        os.chmod(temporary, 0o600)
        os.replace(temporary, path)
      '';
in
{
  options.fullNix.adbShell.allowedSsidsFile = lib.mkOption {
    type = lib.types.nullOr lib.types.str;
    default = null;
    example = "/run/user/secrets/wifi/home-ssids";
    description = ''
      Like `allowedSsids`, but read at activation from this file, one Wi-Fi
      name per line: a secret path, so the names stay out of the Nix store.
      An unreadable file leaves the property unchanged.
    '';
  };

  options.fullNix.adbShell.allowedSsids = lib.mkOption {
    type = lib.types.listOf lib.types.str;
    default = [ ];
    example = [ "home-lan" ];
    description = ''
      Exact Wi-Fi names on which the TermuxPP ADB shell listener may run
      (`adb-shell-allowed-ssids`). An empty list leaves the property untouched,
      so a value set in the app stays in force. Keep the real names in the
      private configuration.
    '';
  };

  # The app reads this file outside the guest, like the appearance files.
  config = {
    assertions = [
      {
        assertion = cfg.allowedSsids == [ ] || cfg.allowedSsidsFile == null;
        message = "fullNix.adbShell: set allowedSsids or allowedSsidsFile, not both";
      }
    ];

    # After sops-nix, which decrypts a secret allowedSsidsFile.
    home.activation.termuxppAdbShellSsids =
      lib.mkIf (cfg.allowedSsids != [ ] || cfg.allowedSsidsFile != null)
        (
          lib.hm.dag.entryAfter [ "writeBoundary" "sops-nix" ] (
            if cfg.allowedSsidsFile != null then
              ''
                run ${setAllowedSsids} ${lib.escapeShellArg properties} --file ${lib.escapeShellArg cfg.allowedSsidsFile}
              ''
            else
              ''
                run ${setAllowedSsids} ${lib.escapeShellArg properties} ${lib.escapeShellArg (lib.concatStringsSep "," cfg.allowedSsids)}
              ''
          )
        );
  };
}
