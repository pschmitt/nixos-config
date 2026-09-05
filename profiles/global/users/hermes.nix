{ pkgs, ... }:
{
  # Dedicated, unprivileged account for Hermes' playwright-mcp SSH access (see
  # services/hermes.nix). Kept separate from nix-remote-builder so a leaked
  # Hermes credential doesn't also grant the Nix distributed-build trust that
  # account carries.
  users.users.hermes = {
    isSystemUser = true;
    description = "Hermes agent playwright-mcp SSH access (see services/hermes.nix)";
    group = "hermes";
    shell = pkgs.bash;
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOuMa/MglO4MOXG9mALoFZQHnpe67vgP5wZGSOKGQs7/ hermes@nixos-config"
    ];
  };

  users.groups.hermes = { };
}
