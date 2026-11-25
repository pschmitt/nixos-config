{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib) mkOption types;
  inherit (config) services;
  serviceType = types.submodule {
    options = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Start this guest service when a Nix guest session opens.";
      };
      command = mkOption {
        type = types.nonEmptyListOf types.str;
        description = "Executable and arguments to run under supervision.";
      };
      environment = mkOption {
        type = types.attrsOf types.str;
        default = { };
        description = "Environment values passed to the service process.";
      };
      workingDirectory = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Working directory for the service.";
      };
      notification = mkOption {
        type = types.nullOr types.bool;
        default = null;
        description = "Show a notification while this service runs. Null uses nixpp.serviceNotifications.enable.";
      };
      allowedSsids = mkOption {
        type = types.listOf types.str;
        default = [ ];
        example = [ "home-lan" ];
        description = ''
          Exact Wi-Fi names on which this service may run. The TermuxPP app
          publishes the current network to the runtime directory, and the
          guest supervisor starts and stops the service as it changes; with
          no Wi-Fi, an unknown name or stale network state the service stays
          down. An empty list means no restriction. Keep the real names in
          the private configuration.
        '';
      };
      allowedSsidsFile = mkOption {
        type = types.nullOr types.str;
        default = null;
        example = "/run/secrets/wifi/home-ssids";
        description = ''
          Like `allowedSsids`, but read at runtime from this file, one Wi-Fi
          name per line: a secret path, so the names stay out of the Nix
          store. An unreadable file allows no network.
        '';
      };
    };
  };
  serviceDirectories = lib.mapAttrs (
    name: service:
    let
      environmentArguments = lib.concatStringsSep " " (
        map lib.escapeShellArg (
          [
            "HOME=${config.user.home}"
            "USER=${config.user.name}"
            "LOGNAME=${config.user.name}"
            "PATH=${config.user.home}/.nix-profile/bin:/run/current-system/sw/bin:/bin:/usr/bin"
          ]
          ++ lib.mapAttrsToList (key: value: "${key}=${value}") service.environment
        )
      );
      workingDirectory =
        if service.workingDirectory == null then
          "cd /"
        else
          "cd ${lib.escapeShellArg service.workingDirectory}";
      notify =
        service.notification != null && service.notification
        || (service.notification == null && config.nixpp.serviceNotifications.enable);
      notificationId = "nixpp-service-${name}";
      run = pkgs.writeShellScript "nixpp-service-${name}-run" ''
        exec 2>&1
        ${workingDirectory}
        export PATH=${lib.escapeShellArg "${config.user.home}/.nix-profile/bin:/run/current-system/sw/bin:/bin:/usr/bin"}
        notification=${if notify then "true" else "false"}
        settings=/run/nixpp-runtime/service-state/settings.json
        if [ -r "$settings" ]; then
          override=$(${pkgs.jq}/bin/jq -r --arg name ${lib.escapeShellArg name} 'if .[$name] | type == "object" and has("notification") then .[$name].notification else empty end' "$settings" 2>/dev/null || true)
          case "$override" in true|false) notification=$override ;; esac
        fi
        if [ "$notification" = true ] && command -v tpp >/dev/null 2>&1; then
          timeout 5 tpp notification send --id ${lib.escapeShellArg notificationId} --channel ${lib.escapeShellArg notificationId} --title ${lib.escapeShellArg name} --content "Service is running" --ongoing --alert-once --priority low </dev/null || true
        fi
        exec ${pkgs.coreutils}/bin/env -i "XDG_RUNTIME_DIR=/run/user/$(id -u)" ${environmentArguments} ${lib.escapeShellArgs service.command}
      '';
      finish = pkgs.writeShellScript "nixpp-service-${name}-finish" ''
        export PATH=${lib.escapeShellArg "${config.user.home}/.nix-profile/bin:/run/current-system/sw/bin:/bin:/usr/bin"}
        if command -v tpp >/dev/null 2>&1; then
          timeout 5 tpp notification remove ${lib.escapeShellArg notificationId} </dev/null || true
        fi
      '';
      logRun = pkgs.writeShellScript "nixpp-service-${name}-log-run" ''
        mkdir -p ./main
        cd ./main
        exec ${pkgs.runit}/bin/svlogd -tt -b 10485760 .
      '';
    in
    pkgs.runCommand "nixpp-service-${name}" { } ''
      mkdir -p "$out/log"
      install -m 0755 ${run} "$out/run"
      install -m 0755 ${finish} "$out/finish"
      install -m 0755 ${logRun} "$out/log/run"
    ''
  ) services;
  manifest = (pkgs.formats.json { }).generate "nixpp-services.json" (
    lib.mapAttrs (name: service: {
      enabled = service.enable;
      inherit (service) allowedSsids allowedSsidsFile;
      directory = toString serviceDirectories.${name};
    }) services
  );
  serviceCommand = pkgs.writeShellApplication {
    name = "svc";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.inotify-tools
      pkgs.jq
      pkgs.procps
      pkgs.runit
      pkgs.util-linux
    ];
    text = builtins.readFile ./scripts/svc.sh;
  };
in
{
  options.services = mkOption {
    type = types.attrsOf serviceType;
    default = { };
    description = "Declarative services supervised within the Android guest.";
  };

  options.nixpp.serviceNotifications.enable = lib.mkEnableOption "running guest service notifications by default";

  config = {
    assertions = lib.concatLists (
      lib.mapAttrsToList (
        name: service:
        [
          {
            assertion = builtins.match "[a-zA-Z0-9][a-zA-Z0-9_.@-]*" name != null;
            message = "services.${name} must use a valid service name";
          }
          {
            assertion = lib.hasPrefix "/" (builtins.head service.command);
            message = "services.${name}.command must use an absolute executable path";
          }
          {
            assertion = name != "adb-shell";
            message = "adb-shell belongs to the TermuxPP app; restrict it with nixpp.adbShell.allowedSsids";
          }
          {
            assertion = lib.all (ssid: ssid != "" && !(lib.hasInfix "," ssid)) service.allowedSsids;
            message = "services.${name}.allowedSsids entries must be non-empty and contain no comma";
          }
          {
            assertion = service.allowedSsids == [ ] || service.allowedSsidsFile == null;
            message = "services.${name}: set allowedSsids or allowedSsidsFile, not both";
          }
          {
            assertion = service.allowedSsidsFile == null || lib.hasPrefix "/" service.allowedSsidsFile;
            message = "services.${name}.allowedSsidsFile must be an absolute path";
          }
        ]
        ++ lib.mapAttrsToList (key: _value: {
          assertion = builtins.match "[A-Za-z_][A-Za-z0-9_]*" key != null;
          message = "services.${name}.environment.${key} must use a valid variable name";
        }) service.environment
      ) services
    );
    environment.systemPackages = [ serviceCommand ];
    environment.etc."nixpp/services.json".source = manifest;
  };
}
