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

    touchscreen = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Whether this host has a touchscreen.";
    };

    provisionSshKeys = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Whether per-host SSH key secrets live in host.sopsFile and should be provisioned.";
    };

    manageAuthorizedKeys = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Whether to manage ~/.ssh/authorized_keys from mainUser.authorizedKeys.
        NixOS hosts already get this via users.users.<name>.openssh.authorizedKeys;
        enable this only on standalone (non-NixOS) home-manager hosts.
      '';
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
      iioTransformMap = lib.mkOption {
        type = lib.types.nullOr (lib.types.listOf lib.types.int);
        default = null;
        description = ''
          Optional `iio-hyprland --transform` mapping for the internal monitor,
          ordered as normal,left-up,bottom-up,right-up.
        '';
      };
    };

    extraAutostartEntries = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Additional XDG autostart desktop files for this host.";
    };

  };
}
