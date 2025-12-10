{ config, pkgs, ... }:
{
  users.users.github-actions = {
    isSystemUser = true;
    description = "Github Actions";
    group = "github-actions";
    shell = pkgs.bash;
    home = "/var/lib/github-actions";
    createHome = true;
    extraGroups = [
      "docker"
      "wheel"
    ];
    openssh.authorizedKeys.keys = config.mainUser.authorizedKeys ++ [
      # Github Actions
      # https://github.com/pschmitt/nixos-config/settings/secrets/actions
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIN6Luwh05e39m7lx9CDyZNicRpHYerLx8fXMwn3o5xHW github-actions@nixos-config"
    ];
  };

  users.groups.github-actions = { };
  nix.settings.trusted-users = [ "github-actions" ];
}
