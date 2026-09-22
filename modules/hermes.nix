{ lib, ... }:
{
  options.custom.hermes.sshPublicKey = lib.mkOption {
    type = lib.types.str;
    default = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOuMa/MglO4MOXG9mALoFZQHnpe67vgP5wZGSOKGQs7/ hermes@nixos-config";
    description = ''
      Hermes agent's SSH public key (see services/hermes.nix). Shared so it
      is defined once and reused by every module that authorizes it:
      profiles/base/users/hermes.nix, profiles/base/users/nix-remote-builder.nix,
      and the same shared user module on fnuc.
    '';
  };
}
