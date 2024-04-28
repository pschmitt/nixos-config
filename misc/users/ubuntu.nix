{ config, ... }:
{
  users.users.ubuntu = {
    uid = 1001;
    group = "ubuntu";
    isNormalUser = true;
    description = "Fake ubuntu user for nixos-anywhere";
    extraGroups = [
      "wheel"
    ];
    openssh.authorizedKeys.keys = config.custom.authorizedKeys;
  };

  users.groups.ubuntu.gid = 1001;
}
