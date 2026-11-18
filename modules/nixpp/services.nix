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
      run = pkgs.writeShellScript "nixpp-service-${name}-run" ''
        ${workingDirectory}
        exec ${pkgs.coreutils}/bin/env -i "XDG_RUNTIME_DIR=/run/user/$(id -u)" ${environmentArguments} ${lib.escapeShellArgs service.command}
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
      install -m 0755 ${logRun} "$out/log/run"
    ''
  ) services;
  manifest = (pkgs.formats.json { }).generate "nixpp-services.json" (
    lib.mapAttrs (name: service: {
      enabled = service.enable;
      directory = toString serviceDirectories.${name};
    }) services
  );
  serviceCommand = pkgs.writeShellApplication {
    name = "svc";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.jq
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
