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

    lockscreenOutputs = lib.mkOption {
      type = lib.types.listOf (
        lib.types.submodule {
          options = {
            name = lib.mkOption {
              type = lib.types.str;
              description = "Wayland output/connector name, e.g. \"eDP-1\" or \"DP-3\".";
            };
            logicalWidth = lib.mkOption {
              type = lib.types.float;
              description = ''
                This output's logical width in px, i.e. its Hyprland-reported
                mode width/height already adjusted for transform (rotation)
                and scale -- what `hyprctl monitors` calls "logical" and
                Noctalia's own log line reports as `logical=WxH`.
              '';
            };
            logicalHeight = lib.mkOption {
              type = lib.types.float;
              description = "This output's logical height in px. See logicalWidth.";
            };
          };
        }
      );
      default = [ ];
      description = ''
        Outputs Noctalia's custom lockscreen_widgets (see
        profiles/laptop/noctalia.nix) should be duplicated onto, with each
        one's real logical size. Noctalia has no "show on every output"
        widget mode of its own (that's bespoke-coded for its login_box only,
        not generic widgets), so getting the same layout on every screen
        means declaring one full widget set per output; this is the list
        that drives that. Empty means unmeasured/unknown for this host --
        consumers should skip lockscreen_widgets placement entirely rather
        than guess using another host's or another output's numbers.
      '';
    };

    extraAutostartEntries = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Additional XDG autostart desktop files for this host.";
    };

  };
}
