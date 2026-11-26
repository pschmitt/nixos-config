{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.nixpp;
  yamlFormat = pkgs.formats.yaml { };
  dir = "${config.xdg.configHome}/termuxpp";
  path = "${dir}/config.yaml";
  settings = pkgs.writeText "termuxpp-settings.json" (builtins.toJSON cfg.settings);
  # Write the whole file: the settings from Nix, plus the ADB shell allow-list
  # read from a secret at activation, so the Wi-Fi names stay out of the store.
  writeSettings =
    pkgs.writers.writePython3 "termuxpp-write-settings"
      {
        libraries = [ pkgs.python3Packages.pyyaml ];
      }
      ''
        import json
        import os
        import sys

        import yaml

        path, settings, mode = sys.argv[1], sys.argv[2], sys.argv[3]
        with open(settings, encoding="utf-8") as source:
            config = json.load(source)
        names = None
        if mode == "--file":
            # One Wi-Fi name per line. Without the file, allow no network
            # rather than any: the app treats an empty list as unrestricted.
            try:
                with open(sys.argv[4], encoding="utf-8") as source:
                    names = [line.strip() for line in source]
            except OSError as error:
                print(f"config.yaml: {error}; ADB shell allow-list "
                      "unreadable, allowing no network", file=sys.stderr)
                names = ["-"]
        elif mode == "--value":
            names = sys.argv[4].split(",")
        if names is not None:
            integrations = config.setdefault("integrations", {})
            adb_shell = integrations.setdefault("adb-shell", {})
            adb_shell["allowed-ssids"] = ",".join(n for n in names if n)

        content = (
            "# Managed by Home Manager (nixos-config). Edits here and in the\n"
            "# app are overwritten on activation.\n"
            + yaml.safe_dump(config, sort_keys=False, allow_unicode=True,
                             default_flow_style=False, width=1000)
        )
        try:
            with open(path, encoding="utf-8") as current:
                unchanged = current.read() == content
        except OSError:
            unchanged = False
        if not unchanged:
            os.makedirs(os.path.dirname(path), exist_ok=True)
            temporary = path + ".tmp"
            with open(temporary, "w", encoding="utf-8") as target:
                target.write(content)
            os.chmod(temporary, 0o600)
            os.replace(temporary, path)
        # The former Java properties file this module wrote. The app migrates
        # it only when there is no YAML file; with one, it is just stale.
        for legacy in ("termuxpp.properties", "termuxpp.properties.migrated"):
            try:
                os.remove(os.path.join(os.path.dirname(path), legacy))
            except FileNotFoundError:
                pass
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
  options.nixpp.settings = lib.mkOption {
    inherit (yamlFormat) type;
    default = { };
    example = {
      terminal.bell = "vibrate";
      extra-keys.swipe.long-left.action = "new-session";
    };
    description = ''
      The TermuxPP app's settings, written to config.yaml in its grouped
      layout (see docs/en/terminal-settings.md in the TermuxPP repository).
      The whole file is written on activation from these settings and
      `nixpp.adbShell`; edits made in the file or in the app's settings are
      overwritten. Nothing is written while this is empty and no ADB shell
      allow-list is set.
    '';
  };

  # The app reads this file outside the guest, like the appearance files.
  # After sops-nix, which decrypts a secret allowedSsidsFile.
  config.home.activation.termuxppSettings =
    lib.mkIf
      (cfg.settings != { } || cfg.adbShell.allowedSsidsFile != null || cfg.adbShell.allowedSsids != [ ])
      (
        lib.hm.dag.entryAfter [ "writeBoundary" "sops-nix" ] ''
          run ${writeSettings} ${lib.escapeShellArg path} ${settings} ${ssidArguments}
        ''
      );
}
