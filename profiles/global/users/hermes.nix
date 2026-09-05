{
  config,
  lib,
  pkgs,
  ...
}:
{
  # Dedicated account for Hermes' SSH access (see services/hermes.nix). On
  # most hosts this is purely an unprivileged playwright-mcp SSH target, kept
  # separate from nix-remote-builder so a leaked Hermes credential doesn't
  # also grant the Nix distributed-build trust that account carries. On
  # rofl-10, this same "hermes" account already exists as the hermes-agent
  # service user (inputs.hermes-agent.nixosModules.default sets isSystemUser/
  # group/shell there too) — the scalar fields below are mkDefault so they
  # yield to that real definition instead of conflicting with it.
  users.users.hermes = {
    isSystemUser = lib.mkDefault true;
    description = lib.mkDefault "Hermes agent playwright-mcp SSH access (see services/hermes.nix)";
    group = lib.mkDefault "hermes";
    shell = lib.mkDefault pkgs.bash;
    openssh.authorizedKeys.keys = [ config.custom.hermes.sshPublicKey ];
  };

  users.groups.hermes = lib.mkDefault { };
}
