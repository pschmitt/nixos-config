{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  # DIRTYFIX for ssh keys transferred via nixos-anywhere's --extra-files option
  # All files are owned by root, which makes sops-nix unhappy
  fixSshOwnership = pkgs.writeShellScript "hm-fix-ssh-ownership" ''
    SUDO_BIN="/run/wrappers/bin/sudo"
    DIR='${config.mainUser.homeDirectory}/.ssh'

    if [[ ! -d "$DIR" ]]
    then
      exit 0
    fi

    echo "Ensuring ownership on $DIR"
    if ! "$SUDO_BIN" -n ${pkgs.coreutils}/bin/chown \
       -R "${config.mainUser.username}:${config.mainUser.username}" "$DIR"
    then
      echo "Could not change ownership on $DIR (needs passwordless sudo)" >&2
      exit 1
    fi
  '';

in
{
  imports = [ inputs.sops-nix.homeManagerModules.sops ];

  sops = {
    defaultSopsFile = config.host.sopsDefaultFile;
    age = {
      generateKey = false;
      sshKeyPaths = [ "${config.mainUser.homeDirectory}/.ssh/id_ed25519" ];
    };
  };

  # Only relevant on hosts provisioned via nixos-anywhere (root-owned keys);
  # skipped on standalone hosts where it would just fail-harmlessly.
  systemd.user.services.sops-nix.Service.ExecStartPre = lib.mkIf config.host.provisionSshKeys (
    lib.mkBefore [ "-${fixSshOwnership}" ]
  );
}
