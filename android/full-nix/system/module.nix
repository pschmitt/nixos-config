{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib) mkOption types;
  cfg = config;
  etcEntry = types.submodule {
    options = {
      text = mkOption {
        type = types.nullOr types.lines;
        default = null;
        description = "Contents of a guest system configuration file.";
      };
      source = mkOption {
        type = types.nullOr types.path;
        default = null;
        description = "Store-backed source for a guest system configuration file.";
      };
    };
  };
  etcFiles = lib.mapAttrsToList (name: value: {
    inherit name;
    path = if value.text != null then pkgs.writeText "guest-etc-file" value.text else value.source;
  }) cfg.environment.etc;
  systemPath = pkgs.buildEnv {
    name = "termuxpp-system-path";
    paths = cfg.environment.systemPackages;
    pathsToLink = [
      "/bin"
      "/share"
    ];
  };
  etc = pkgs.runCommand "termuxpp-system-etc" { } ''
    mkdir -p "$out/etc"
    ${lib.concatMapStringsSep "\n" (entry: ''
      mkdir -p "$out/etc/$(dirname -- ${lib.escapeShellArg entry.name})"
      ln -s ${lib.escapeShellArg (toString entry.path)} "$out/etc/"${lib.escapeShellArg entry.name}
    '') etcFiles}
  '';
  manifest = (pkgs.formats.json { }).generate "termuxpp-system.json" {
    formatVersion = 1;
    inherit (cfg.system) stateVersion;
    inherit (cfg.networking) hostName;
    inherit (cfg.user) name home;
    runtime = "droid-nix";
    activationSupported = false;
    systemPath = toString systemPath;
    homeManager =
      if cfg.home-manager.configuration == null then
        null
      else
        toString cfg.home-manager.configuration.activationPackage;
  };
in
{
  options = {
    assertions = mkOption {
      type = types.listOf types.raw;
      default = [ ];
      internal = true;
    };
    networking.hostName = mkOption {
      type = types.strMatching "[a-zA-Z0-9][a-zA-Z0-9-]*";
      description = "Guest hostname; does not change Android's hostname.";
    };
    user = {
      name = mkOption {
        type = types.strMatching "[a-z_][a-z0-9_-]*";
        description = "Guest user identity; does not create an Android UID.";
      };
      home = mkOption {
        type = types.strMatching "/home/[a-z_][a-z0-9_-]*";
        description = "Persistent guest home directory.";
      };
    };
    environment = {
      systemPackages = mkOption {
        type = types.listOf types.package;
        default = [ ];
        description = "Packages owned by the guest system, independently of Home Manager.";
      };
      etc = mkOption {
        type = types.attrsOf etcEntry;
        default = { };
        description = "Declarative files relative to the guest's /etc directory.";
      };
    };
    home-manager.configuration = mkOption {
      type = types.nullOr types.raw;
      default = null;
      description = "Evaluated Home Manager configuration associated with this system generation.";
    };
    system = {
      stateVersion = mkOption {
        type = types.enum [ "1" ];
        description = "Guest system state schema version, independent of NixOS and HM versions.";
      };
      build.toplevel = mkOption {
        type = types.package;
        readOnly = true;
        internal = true;
      };
    };
  };

  config = {
    assertions = lib.mapAttrsToList (name: value: {
      assertion =
        name != ""
        && !(lib.hasPrefix "/" name)
        && builtins.all (part: part != "" && part != "." && part != "..") (lib.splitString "/" name)
        && ((value.text != null) != (value.source != null));
      message = "environment.etc.${name} must have a safe relative path and exactly one of text/source";
    }) cfg.environment.etc;
    system.build.toplevel = pkgs.runCommand "termuxpp-system-${cfg.networking.hostName}" { } ''
      mkdir -p "$out"
      ln -s ${systemPath} "$out/sw"
      ln -s ${etc}/etc "$out/etc"
      ln -s ${manifest} "$out/manifest.json"
      ${lib.optionalString (cfg.home-manager.configuration != null) ''
        ln -s ${cfg.home-manager.configuration.activationPackage} "$out/home-manager"
      ''}
    '';
  };
}
