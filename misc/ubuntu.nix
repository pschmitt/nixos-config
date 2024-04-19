{ config, ... }:
{
  users.users.ubuntu = {
    isNormalUser = true;
    description = "Fake ubuntu user for nixos-anywhere";
    extraGroups = [
      "wheel"
    ];
    openssh.authorizedKeys.keys = config.custom.authorizedKeys;
  };
}
