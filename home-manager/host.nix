# host.* — system facts the home config needs, kept osConfig-free so the same
# modules work both as a NixOS submodule (facts fed by the bridge in
# ./default.nix) and standalone (facts set explicitly, e.g. hosts/fnuc).
{ lib, ... }:
{
  options.host = {
    sopsFile = lib.mkOption {
      type = lib.types.path;
      default = ../secrets/shared.sops.yaml;
      description = "Host-specific SOPS file (NixOS: config.custom.sopsFile).";
    };

    sopsDefaultFile = lib.mkOption {
      type = lib.types.path;
      default = ../secrets/shared.sops.yaml;
      description = "Default SOPS file for shared secrets.";
    };

    highDpi = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Whether this host has a high-DPI screen.";
    };

    nvidiaPrimeOffload = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Whether NVIDIA PRIME offload is enabled.";
    };

    iioSensor = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Whether an IIO sensor (accelerometer) is present.";
    };

    provisionSshKeys = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Whether per-host SSH key secrets live in host.sopsFile and should be provisioned.";
    };

    uid = lib.mkOption {
      type = lib.types.int;
      default = 1000;
      description = "Main user's uid (used for XDG_RUNTIME_DIR).";
    };

    stateVersion = lib.mkOption {
      type = lib.types.str;
      default = "25.11";
      description = "home.stateVersion (NixOS: system.stateVersion).";
    };

    internalMonitor = {
      scale = lib.mkOption {
        type = lib.types.float;
        default = 1.0;
        description = "HiDPI scale factor for the internal monitor (1.0 = no scaling).";
      };
      transform = lib.mkOption {
        type = lib.types.nullOr lib.types.int;
        default = null;
        description = "Hyprland transform (rotation) for the internal monitor. Null means no rotation.";
      };
    };
  };
}
