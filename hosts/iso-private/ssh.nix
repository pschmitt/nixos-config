{ config, lib, ... }:
{
  systemd.services.sshd.wantedBy = lib.mkForce [ "multi-user.target" ];
  users.users.root.openssh.authorizedKeys.keys = config.mainUser.authorizedKeys ++ [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGvVATHmFG1p5JqPkM2lE7wxCO2JGX3N5h9DEN3T2fKM nixos-anywhere"
  ];
}
