# sops-nix for nix-on-droid. There is no systemd on Android, so the
# sops-nix user service never runs and there is no $XDG_RUNTIME_DIR for the
# default "%r/secrets.d" mount point: decrypt during HM activation instead.
{ config, lib, ... }:
let
  service = config.systemd.user.services.sops-nix.Service;
  # HM unit options are lists after merging.
  unitValue = v: lib.concatStringsSep " " (lib.toList v);
in
{
  imports = [
    ../modules/main-user.nix
    ./host.nix
    ./sops.nix
  ];

  mainUser = {
    inherit (config.home) username homeDirectory;
    sshKey = "${config.home.homeDirectory}/.ssh/id_ed25519";
  };

  sops.defaultSecretsMountPoint = "${config.xdg.stateHome}/sops-nix/secrets.d";

  home.activation.sops-nix = lib.mkForce (
    lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      run env ${unitValue service.Environment} ${unitValue service.ExecStart} \
        || warnEcho "sops-nix: decryption failed, is ~/.ssh/id_ed25519 a recipient?"
    ''
  );
}
