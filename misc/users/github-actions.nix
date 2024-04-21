{ config, ... }:
{
  users.users.github-actions = {
    uid = 10001;
    isNormalUser = true;
    description = "Github Actions";
    extraGroups = [
      "docker"
      "wheel"
    ];
    openssh.authorizedKeys.keys = config.custom.authorizedKeys ++ [
      # Github Actions
      # https://github.com/pschmitt/nixos-config/settings/secrets/actions
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIN6Luwh05e39m7lx9CDyZNicRpHYerLx8fXMwn3o5xHW github-actions@nixos-config"
    ];
  };
}
