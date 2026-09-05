{ lib, ... }:
{
  options.custom.hermes.sshPublicKey = lib.mkOption {
    type = lib.types.str;
    default = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOuMa/MglO4MOXG9mALoFZQHnpe67vgP5wZGSOKGQs7/ hermes@nixos-config";
    description = ''
      Hermes agent's SSH public key (see services/hermes.nix). Shared so it
      is defined once and reused by every module that authorizes it:
      profiles/global/users/hermes.nix, profiles/global/users/nix-remote-builder.nix,
      and hosts/fnuc/default.nix (fnuc has no NixOS user module, so Hermes
      logs in as mainUser there instead of its own dedicated account).
    '';
  };
}
