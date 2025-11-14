{
  lib,
  osConfig,
  pkgs,
  ...
}:
let
  # DIRTYFIX for ssh keys transferred via nixos-anywhere's --extra-files option
  # All files are owned by root, which makes sops-nix unhappy
  fixSshOwnership = pkgs.writeShellScript "hm-fix-ssh-ownership" ''
    SUDO_BIN="/run/wrappers/bin/sudo"
    DIR='${osConfig.custom.homeDirectory}/.ssh'

    if [[ ! -d "$DIR" ]]
    then
      exit 0
    fi

    echo "Ensuring ownership on $DIR"
    if ! "$SUDO_BIN" -n chown -R "${osConfig.custom.username}:${osConfig.custom.username}" "$DIR"
    then
      echo "Could not change ownership on $DIR (needs passwordless sudo)" >&2
      exit 1
    fi
  '';

in
{
  sops = {
    inherit (osConfig.sops) defaultSopsFile;
    age = {
      generateKey = false;
      sshKeyPaths = [ "${osConfig.custom.homeDirectory}/.ssh/id_ed25519" ];
    };
  };

  # systemd.user.services.sops-nix.Service.ExecStartPre = lib.mkBefore [ "-${fixSshOwnership}" ];
}
