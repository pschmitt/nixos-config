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
    openssh.authorizedKeys.keys = config.custom.authorizedKeys ++ [
      # Github Actions
      # https://github.com/pschmitt/nixos-config/settings/secrets/actions
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIN6Luwh05e39m7lx9CDyZNicRpHYerLx8fXMwn3o5xHW github-actions@nixos-config"
      # rofl-02 host key TODO Remove
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHj1bwykYI4tC4kt3Rd4QAOV2D1srlcQ14NLB9w3JBXp root@rofl-02"
      # rofl-09 host key
      # ssh r9 sudo cat /etc/ssh/ssh_host_ed25519_key.pub
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIM1RQuD12+CL5NzJHrVge49uK9QyPlISobQG5MNgIZHo root@rofl-09"
    ];
  };

  users.groups.github-actions = { };
  nix.settings.trusted-users = [ "github-actions" ];
}
