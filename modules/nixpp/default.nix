{
  config,
  inputs,
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
  systemTools = (inputs.termuxpp.lib.nixpp.packagesFor pkgs).nixpp;
  systemPath = pkgs.buildEnv {
    name = "termuxpp-system-path";
    paths = cfg.environment.systemPackages ++ [ systemTools ];
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
  secretsActivation = cfg.system.build.secretsActivation;
  manifest = (pkgs.formats.json { }).generate "termuxpp-system.json" (
    {
      formatVersion = 1;
      inherit (cfg.system) stateVersion;
      inherit (cfg.networking) hostName;
      inherit (cfg.user) name home;
      runtime = "droid-nix";
      activationSupported = cfg.home-manager.configuration != null;
      systemPath = toString systemPath;
      session = {
        shell = "${pkgs.bashInteractive}/bin/bash";
        certificate = "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";
        terminfo = "${pkgs.ncurses}/share/terminfo";
      };
      homeManager =
        if cfg.home-manager.configuration == null then
          null
        else
          toString cfg.home-manager.configuration.activationPackage;
    }
    // lib.optionalAttrs (secretsActivation != null) {
      # Store path of an executable the runtime runs in the selected candidate
      # before the Home Manager activation. Absent in generations without it.
      systemSecrets = "${secretsActivation}/bin/activate-secrets";
    }
  );
in
{
  imports = [
    ./services.nix
    ./sops.nix
  ];

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
      homeManagerBackupExtension = mkOption {
        type = types.nullOr (types.strMatching "[A-Za-z0-9][A-Za-z0-9._-]{0,31}");
        default = "nixpp.bak";
        example = "hm-old";
        description = ''
          The extension under which `nixpp switch`, `upgrade`, `rebuild` and
          `fetch` (the nightly upgrade too) have Home
          Manager move an existing, unmanaged file that blocks its activation
          to `<file>.<extension>` (HOME_MANAGER_BACKUP_EXT) instead of failing
          with "would be clobbered". An existing `<file>.<extension>` is never
          overwritten: the activation fails and says so. Written to
          /etc/nixpp/upgrade.json by the system profile; `--no-backup`
          overrides it for one run, `--backup=EXT` sets another extension for
          one run. null turns backups off: the activation then fails on such
          files. Default: nixpp.bak, which enforces the Nix configuration.
        '';
      };
      nativeNixpp = mkOption {
        type = types.nullOr types.package;
        default = null;
        description = ''
          The native (Android/Bionic) nixpp shipped with this generation as
          native/nixpp. After switching to the generation the native daemon
          installs it when it differs from its own executable and restarts,
          so native changes reach existing installs with the guest system
          instead of only with a fresh bootstrap.
        '';
      };
    };
  };

  config = {
    environment.etc.protocols.source = lib.mkDefault "${pkgs.iana-etc}/etc/protocols";

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
      ${lib.optionalString (cfg.system.nativeNixpp != null) ''
        mkdir -p "$out/native"
        ln -s ${lib.getExe cfg.system.nativeNixpp} "$out/native/nixpp"
      ''}
      ${lib.optionalString (secretsActivation != null) ''
        mkdir -p "$out/bin"
        ln -s ${secretsActivation}/bin/activate-secrets "$out/bin/activate-secrets"
      ''}
      ${lib.optionalString (cfg.home-manager.configuration != null) ''
        ln -s ${cfg.home-manager.configuration.activationPackage} "$out/home-manager"
      ''}
    '';
  };
}
