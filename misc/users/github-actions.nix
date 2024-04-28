{ config, ... }:
{
  users.users.github-actions = {
    isNormalUser = false;
    description = "Github Actions";
    extraGroups = [
      "docker"
      "wheel"
    ];
    openssh.authorizedKeys.keys = config.custom.authorizedKeys ++ [
      # Github Actions
      # https://github.com/pschmitt/nixos-config/settings/secrets/actions
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIN6Luwh05e39m7lx9CDyZNicRpHYerLx8fXMwn3o5xHW github-actions@nixos-config"
      # rofl-02 host key
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHj1bwykYI4tC4kt3Rd4QAOV2D1srlcQ14NLB9w3JBXp root@rofl-02"
    ];
  };
}
