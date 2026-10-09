# Typed Monit service checks, rendered into services.monit.config.
#
#   services.monit.checks.postgresql = {
#     type = "program";
#     path = "${pkg}/bin/pg_isready -q";
#     group = "database";
#     restartUnit = "postgresql.service";
#     conditions = ''
#       if status > 0 then restart
#       if 5 restarts within 10 cycles then alert
#     '';
#   };
#
# The service header (target, group, dependencies, start/stop/restart
# programs, polling cycle) is typed; the rule statements stay plain Monit
# syntax in `conditions`.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib)
    concatMapStringsSep
    concatStringsSep
    filter
    filterAttrs
    mapAttrsToList
    mkAfter
    mkIf
    mkOption
    optional
    optionalString
    splitString
    types
    ;

  checks = filterAttrs (_: c: c.enable) config.services.monit.checks;

  indent =
    text:
    concatStringsSep "\n" (
      map (line: if line == "" then "" else "  " + line) (splitString "\n" (lib.removeSuffix "\n" text))
    );

  render =
    _: c:
    let
      target =
        if c.address != null then
          " with address \"${c.address}\""
        else if c.path != null then
          " with path \"${c.path}\""
        else if c.pidfile != null then
          " with pidfile \"${c.pidfile}\""
        else if c.matching != null then
          " with matching \"${c.matching}\""
        else if c.interface != null then
          " with interface ${c.interface}"
        else
          "";
      restartProgram =
        if c.restartUnit != null then
          "${pkgs.systemd}/bin/systemctl restart ${c.restartUnit}"
        else
          c.restartProgram;
      header =
        map (g: "group \"${g}\"") c.group
        ++
          optional (c.dependsOn != [ ])
            "depends on ${concatMapStringsSep ", " (d: "\"${d}\"") c.dependsOn}"
        ++ optional (c.startProgram != null) "start program = \"${c.startProgram}\""
        ++ optional (c.stopProgram != null) "stop program = \"${c.stopProgram}\""
        ++ optional (restartProgram != null) (
          "restart program = \"${restartProgram}\""
          + optionalString (c.restartTimeout != null) " with timeout ${toString c.restartTimeout} seconds"
        )
        ++ optional (c.every != null) (
          if builtins.isInt c.every then "every ${toString c.every} cycles" else "every \"${c.every}\""
        );
      body = concatStringsSep "\n" (
        filter (s: s != "") [
          (indent (concatStringsSep "\n" header))
          (indent c.conditions)
        ]
      );
    in
    ''
      check ${c.type} "${c.name}"${target}
      ${body}
    '';

  checkModule =
    { name, ... }:
    {
      options = {
        enable = mkOption {
          type = types.bool;
          default = true;
          description = "Whether to render this check.";
        };

        name = mkOption {
          type = types.str;
          default = name;
          description = "Monit service name.";
        };

        type = mkOption {
          type = types.enum [
            "directory"
            "file"
            "filesystem"
            "host"
            "network"
            "process"
            "program"
            "system"
          ];
          description = "Monit service type (`check <type> ...`).";
        };

        address = mkOption {
          type = types.nullOr types.str;
          default = null;
          description = "Address of a `host` check.";
        };

        path = mkOption {
          type = types.nullOr types.str;
          default = null;
          description = "Path (or command line, for `program`) of the check; rendered quoted.";
        };

        pidfile = mkOption {
          type = types.nullOr types.str;
          default = null;
          description = "Pidfile of a `process` check.";
        };

        matching = mkOption {
          type = types.nullOr types.str;
          default = null;
          description = "Process pattern of a `process` check; rendered quoted.";
        };

        interface = mkOption {
          type = types.nullOr types.str;
          default = null;
          description = "Interface of a `network` check.";
        };

        group = mkOption {
          type = types.coercedTo types.str lib.singleton (types.listOf types.str);
          default = [ ];
          description = "Monit service group(s).";
        };

        dependsOn = mkOption {
          type = types.listOf types.str;
          default = [ ];
          description = "Services this check depends on.";
        };

        startProgram = mkOption {
          type = types.nullOr types.str;
          default = null;
          description = "Start program command line.";
        };

        stopProgram = mkOption {
          type = types.nullOr types.str;
          default = null;
          description = "Stop program command line.";
        };

        restartProgram = mkOption {
          type = types.nullOr types.str;
          default = null;
          description = "Restart program command line (see also restartUnit).";
        };

        restartUnit = mkOption {
          type = types.nullOr types.str;
          default = null;
          example = "postgresql.service";
          description = "Systemd unit to restart as the restart program.";
        };

        restartTimeout = mkOption {
          type = types.nullOr types.ints.positive;
          default = null;
          description = "Timeout in seconds for the restart program.";
        };

        every = mkOption {
          type = types.nullOr (types.either types.ints.positive types.str);
          default = null;
          example = "0 3 * * *";
          description = "Only test every N cycles, or on a cron schedule (string).";
        };

        conditions = mkOption {
          type = types.lines;
          default = "";
          description = "Monit rule statements (`if ... then ...`).";
        };
      };
    };
in
{
  options.services.monit.checks = mkOption {
    type = types.attrsOf (types.submodule checkModule);
    default = { };
    description = "Typed Monit service checks, appended to services.monit.config.";
  };

  config = mkIf (checks != { }) {
    assertions = mapAttrsToList (n: c: {
      assertion = c.restartUnit == null || c.restartProgram == null;
      message = "services.monit.checks.${n}: set restartUnit or restartProgram, not both.";
    }) checks;

    services.monit.config = mkAfter (concatStringsSep "\n" (mapAttrsToList render checks));
  };
}
