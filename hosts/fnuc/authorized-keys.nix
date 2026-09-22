{ config, lib, ... }:
{
  mainUser.extraAuthorizedKeys = lib.mkAfter [
    # Home Assistant container on hv, used by the KVM USB replug automation.
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKtJvOe/V+obZ1lS2L/qUAUVDUSFapVKin07BUZSHAU7 root@a0d7b954-ssh"
    config.custom.hermes.sshPublicKey
  ];
}
