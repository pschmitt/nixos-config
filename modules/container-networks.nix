# Named OCI networks that declarative containers attach to via
# `virtualisation.oci-containers.containers.<name>.networks`. Each network gets
# a oneshot unit that creates it if missing; containers order themselves after
# that unit through the read-only `unit` attribute.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib) mkOption types;
  inherit (config.virtualisation.oci-containers) backend;
  networks = config.virtualisation.oci-containers.ensureNetworks;
  cli =
    if backend == "docker" then
      lib.getExe config.virtualisation.docker.package
    else
      lib.getExe config.virtualisation.podman.package;

  mkScript =
    name: net:
    pkgs.writeShellScript "${backend}-network-${name}" ''
      if ! ${cli} network inspect ${lib.escapeShellArg name} >/dev/null 2>&1
      then
        ${cli} network create ${lib.escapeShellArgs net.extraArgs} ${lib.escapeShellArg name}
      fi
    '';
in
{
  options.virtualisation.oci-containers.ensureNetworks = mkOption {
    default = { };
    description = "OCI networks to create before the containers that use them start.";
    type = types.attrsOf (
      types.submodule (
        { name, ... }:
        {
          options = {
            extraArgs = mkOption {
              type = types.listOf types.str;
              default = [ ];
              example = [
                "--subnet"
                "10.0.0.0/24"
              ];
              description = "Extra arguments for `network create`.";
            };
            unit = mkOption {
              type = types.str;
              readOnly = true;
              default = "${backend}-network-${name}.service";
              description = "systemd unit that creates this network; add it to a container's requires/after.";
            };
          };
        }
      )
    );
  };

  config = lib.mkIf (networks != { }) {
    systemd.services = lib.mapAttrs' (
      name: net:
      lib.nameValuePair "${backend}-network-${name}" {
        description = "Create the ${name} ${backend} network";
        wantedBy = [ "multi-user.target" ];
        requires = lib.optional (backend == "docker") "docker.service";
        after = lib.optional (backend == "docker") "docker.service";
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = mkScript name net;
        };
      }
    ) networks;
  };
}
