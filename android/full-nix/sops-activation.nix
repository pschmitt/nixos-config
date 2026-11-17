# Activation-time sops-nix adapter shared by the Home Manager layer and the
# declarative guest system layer.
#
# There is no systemd, no root and no daemon in the guest: both layers run as the
# same Android UID. Upstream's installer script (the unit's ExecStart, which also
# handles `age.generateKey`) is executed directly from an activation script, so a
# failed decryption fails the activation that asked for it instead of being
# swallowed by a service restart. Upstream's own cleanup is all there is: no
# state of ours, see the README for what that implies.
#
# Returns the *text* of a bash script (callers wrap it with writeShellScript or
# writeShellScriptBin).
{ lib, pkgs }:
{
  # Upstream's installer script (config.systemd.user.services.sops-nix.Service.ExecStart,
  # a string or, with Home Manager's systemd module, a list of one).
  installer,
  # sops.environment: literal values, applied the way the systemd unit would.
  environment ? { },
  # Used for `%r` when XDG_RUNTIME_DIR is not set in the activating environment.
  runtimeDir,
}:
let
  envPath = environment.PATH or "";
  exports = lib.concatStringsSep "\n" (
    lib.mapAttrsToList (name: value: "export ${name}=${lib.escapeShellArg (toString value)}") (
      lib.filterAttrs (name: value: name != "PATH" && toString value != "") environment
    )
  );
in
''
  set -eu -o pipefail
  export PATH=${
    lib.concatStringsSep ":" (lib.optional (envPath != "") envPath ++ [ "${pkgs.coreutils}/bin" ])
  }''${PATH:+:$PATH}
  ${exports}
  : "''${XDG_RUNTIME_DIR:=${runtimeDir}}"
  export XDG_RUNTIME_DIR
  # The umask a systemd user unit would run with: the installer applies the
  # configured modes itself and a stricter umask would silently strip them.
  umask 022
  exec ${lib.concatStringsSep " " (lib.toList installer)}
''
