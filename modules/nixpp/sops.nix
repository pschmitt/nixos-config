# sops-nix for the declarative guest system layer.
#
# Upstream's NixOS module needs systemd, users and root, so the pinned upstream
# Home Manager module is reused instead: its options (including templates), its
# assertions, its manifest and its installer script come from upstream unchanged.
# It is evaluated against inert option sinks for the few Home Manager and systemd
# options it writes, which nothing reads. No systemd is run or faked: the
# installer script is read back from the unit's `ExecStart` and executed by
# `bin/activate-secrets` of the system toplevel, which the runtime runs before
# the matching Home Manager activation. A non-zero exit fails that activation.
#
# Ownership: the system layer owns `sops.*` here, Home Manager owns its own
# `sops.*` (../home-manager/termuxpp/sops.nix). Both run as the same Android UID, so the separate
# paths are organization, not a security boundary: file modes are the only
# access control and apply to that one UID.
{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib) mkOption types;
  inherit (config) sops;
  script = import ./sops-activation.nix { inherit lib pkgs; };
  sink =
    type:
    mkOption {
      inherit type;
      internal = true;
      visible = false;
      default = { };
    };
in
{
  imports = [ inputs.sops-nix.homeManagerModules.sops ];

  options = {
    # Inert sinks for what upstream's module writes or reads. Only the system
    # layer's own paths are meaningful: `%r` is $XDG_RUNTIME_DIR.
    xdg.configHome = mkOption {
      type = types.str;
      default = "%r/termuxpp-system";
      internal = true;
      visible = false;
    };
    home = {
      username = mkOption {
        type = types.str;
        default = config.user.name;
        internal = true;
        visible = false;
      };
      homeDirectory = mkOption {
        type = types.str;
        default = config.user.home;
        internal = true;
        visible = false;
      };
      sessionVariables = sink (types.attrsOf types.raw);
      activation = sink (types.attrsOf types.raw);
    };
    launchd.agents = sink (types.attrsOf types.raw);
    systemd.user = {
      services = sink (types.attrsOf types.raw);
      systemctlPath = mkOption {
        type = types.str;
        default = "systemctl";
        internal = true;
        visible = false;
      };
    };

    fullNix.sops.runtimeDir = mkOption {
      type = types.str;
      default = "/run";
      description = ''
        XDG_RUNTIME_DIR used for `%r` when the activating environment does not
        set it. Persistent storage in the guest, not tmpfs.
      '';
    };

    system.build.secretsActivation = mkOption {
      type = types.nullOr types.package;
      readOnly = true;
      internal = true;
      description = "Derivation providing bin/activate-secrets, or null without secrets.";
    };
  };

  config = {
    # Separate from Home Manager's `%r/secrets.d`.
    sops.defaultSecretsMountPoint = lib.mkDefault "/run/secrets.d";
    sops.defaultSymlinkPath = lib.mkDefault "/run/secrets";

    system.build.secretsActivation =
      if sops.secrets == { } then
        null
      else
        pkgs.writeShellScriptBin "activate-secrets" (script {
          installer = config.systemd.user.services.sops-nix.Service.ExecStart;
          inherit (sops) environment;
          inherit (config.fullNix.sops) runtimeDir;
        });
  };
}
