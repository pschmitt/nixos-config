{ config, ... }:
{
  # Enable lingering
  systemd.tmpfiles.rules = [ "f /var/lib/systemd/linger/${config.custom.username}" ];

  users.users."${config.custom.username}" = {
    linger = true;

    extraGroups = [
      "input" # do we need this?
      "uinput" # for dotool
      "video" # do we need this?
    ];
  };
}
