# sops-nix for the Android guest Home Manager layer.
#
# The pinned upstream Home Manager module is reused unchanged for options,
# manifest generation, validation and the installer script. Only its activation
# is replaced: upstream restarts a systemd user unit, which does not exist here.
# Instead the installer runs inside Home Manager activation, so a failure aborts
# the activation. Runs as the guest's single Android UID, like the system layer
# (see ../../nixpp/sops.nix); the two layers use separate paths.
{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.nixpp.sops;
  inherit (config) sops;
  hasSecrets = sops.secrets != { };
  script = import ../../nixpp/sops-activation.nix { inherit lib pkgs; };
  activation = pkgs.writeShellScript "sops-nix-activate-hm" (script {
    installer = config.systemd.user.services.sops-nix.Service.ExecStart;
    inherit (sops) environment;
    inherit (cfg) runtimeDir disableGoGc;
  });
in
{
  imports = [ inputs.sops-nix.homeManagerModules.sops ];

  options.nixpp.sops = {
    runtimeDir = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = ''
        XDG_RUNTIME_DIR used for `%r` when the activating environment does not set
        it. A null value uses /run/user/<uid>.
      '';
    };

    disableGoGc = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Run the sops-nix installer with Go's garbage collector off (`GOGC=off`).
        A workaround for devices whose guest runtime corrupts Go's heap during
        garbage collection (seen on zf10: Android 15, kernel 5.15). Leave it off
        elsewhere: without a GC the installer can grow to several GiB, and
        Android's per-app memory limiter then kills the app mid-activation.
      '';
    };

    activation = lib.mkOption {
      type = lib.types.nullOr lib.types.package;
      readOnly = true;
      internal = true;
      description = "Script run by the sops-nix activation entry; null without secrets.";
    };
  };

  config = lib.mkMerge [
    { nixpp.sops.activation = if hasSecrets then activation else null; }
    (lib.mkIf hasSecrets {
      # No systemd in the guest: do not ship upstream's unit files.
      xdg.configFile = {
        "systemd/user/sops-nix.service".enable = lib.mkForce false;
        "systemd/user/default.target.wants/sops-nix.service".enable = lib.mkForce false;
        "systemd/user/graphical-session-pre.target.wants/sops-nix.service".enable = lib.mkForce false;
      };

      home.activation.sops-nix = lib.mkForce (
        lib.hm.dag.entryBetween
          [ "androidAcceptance" ]
          [
            "linkGeneration"
            "onFilesChange"
          ]
          ''
            run ${activation}
          ''
      );
    })
  ];
}
