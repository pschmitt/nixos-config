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
  config.home.activation.termuxppAdbShellSsids = lib.mkIf (cfg.allowedSsids != [ ]) (
    lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      run ${setAllowedSsids} ${lib.escapeShellArg properties} ${lib.escapeShellArg (lib.concatStringsSep "," cfg.allowedSsids)}
    ''
  );
}
