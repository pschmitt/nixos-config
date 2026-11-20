{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.fullNix;
  path = "${config.xdg.configHome}/termuxpp/termuxpp.properties";
  settings = pkgs.writeText "termuxpp-properties.json" (builtins.toJSON cfg.properties);
  # Write the whole file: the settings from Nix, plus the ADB shell allow-list
  # read from a secret at activation, so the Wi-Fi names stay out of the store.
  writeProperties =
    pkgs.writers.writePython3 "termuxpp-write-properties"
      {
        libraries = [ pkgs.python3Packages.javaproperties ];
      }
      ''
        import io
        import json
        import os
        import sys

        import javaproperties

        path, settings, mode = sys.argv[1], sys.argv[2], sys.argv[3]
        with open(settings, encoding="utf-8") as source:
            props = {
                key: (str(value).lower() if isinstance(value, bool)
                      else str(value))
                for key, value in json.load(source).items()
            }
        if mode == "--file":
            # One Wi-Fi name per line. Without the file, allow no network
            # rather than any: the app treats an empty list as unrestricted.
            try:
                with open(sys.argv[4], encoding="utf-8") as source:
                    names = [line.strip() for line in source]
            except OSError as error:
                print(f"termuxpp.properties: {error}; ADB shell allow-list "
                      "unreadable, allowing no network", file=sys.stderr)
                names = ["-"]
            props["adb-shell-allowed-ssids"] = ",".join(n for n in names if n)
        elif mode == "--value":
            props["adb-shell-allowed-ssids"] = sys.argv[4]

        buffer = io.StringIO()
        javaproperties.dump(
            props, buffer, timestamp=False,
            comments="Managed by Home Manager (nixos-config). "
                     "Edits here and in the app are overwritten on activation.")
        content = buffer.getvalue()
        try:
            with open(path, encoding="utf-8") as current:
                if current.read() == content:
                    sys.exit(0)
        except OSError:
            pass
        os.makedirs(os.path.dirname(path), exist_ok=True)
        temporary = path + ".tmp"
        with open(temporary, "w", encoding="utf-8") as target:
            target.write(content)
        os.chmod(temporary, 0o600)
        os.replace(temporary, path)
      '';
  ssidArguments =
    if cfg.adbShell.allowedSsidsFile != null then
      "--file ${lib.escapeShellArg cfg.adbShell.allowedSsidsFile}"
    else if cfg.adbShell.allowedSsids != [ ] then
      "--value ${lib.escapeShellArg (lib.concatStringsSep "," cfg.adbShell.allowedSsids)}"
    else
      "--none";
in
{
  options.fullNix.properties = lib.mkOption {
    type =
      with lib.types;
      attrsOf (oneOf [
        str
        int
        bool
      ]);
    default = { };
    example = {
      bell-character = "vibrate";
      extra-keys-long-swipe-left-action = "new-session";
    };
    description = ''
      The TermuxPP app's termuxpp.properties. The whole file is written on
      activation from these settings and `fullNix.adbShell`; edits made in the
      file or in the app's properties editor are overwritten. Nothing is
      written while this is empty and no ADB shell allow-list is set.
    '';
  };

  # The app reads this file outside the guest, like the appearance files.
  # After sops-nix, which decrypts a secret allowedSsidsFile.
  config.home.activation.termuxppProperties =
    lib.mkIf
      (cfg.properties != { } || cfg.adbShell.allowedSsidsFile != null || cfg.adbShell.allowedSsids != [ ])
      (
        lib.hm.dag.entryAfter [ "writeBoundary" "sops-nix" ] ''
          run ${writeProperties} ${lib.escapeShellArg path} ${settings} ${ssidArguments}
        ''
      );
}
