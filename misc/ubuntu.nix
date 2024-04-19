{ config, ... }:
{
  users.users.ubuntu = {
    uid = 1001;
    isNormalUser = true;
    description = "Fake ubuntu user for nixos-anywhere";
    extraGroups = [
      "wheel"
    ];
    openssh.authorizedKeys.keys = config.custom.authorizedKeys;
  };
}
