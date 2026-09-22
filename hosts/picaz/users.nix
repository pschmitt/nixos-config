{ config, pkgs, ... }:
{
  users = {
    mutableUsers = false;
    users."${config.mainUser.username}" = {
      isNormalUser = true;
      hashedPassword = "!";
      extraGroups = [
        "wheel"
        "video"
      ];
      openssh.authorizedKeys.keys = config.mainUser.authorizedKeys;
      shell = pkgs.bash;
    };
    groups."${config.mainUser.username}" = { };
  };

  security.sudo.wheelNeedsPassword = false;
}
