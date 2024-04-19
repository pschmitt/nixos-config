{ config, ... }:
{

  users.users.github-actions = {
    isNormalUser = true;
    description = "Github Actions";
    extraGroups = [
      "docker"
      "wheel"
    ];
    openssh.authorizedKeys.keys = config.custom.authorizedKeys ++ [
      # Github Actions
      # https://github.com/pschmitt/nixos-config/settings/secrets/actions
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDkBdjd6CHCNvfKkCXQHUb4y/vaNr3SSGb7EZDERw9yk github-actions@nixos-config"
    ];
  };
}
