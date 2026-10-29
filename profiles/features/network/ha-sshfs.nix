{ config, ... }:
{
  services.sshfs.mounts.home-assistant = {
    mountPoint = "/mnt/ha";
    host = config.services.home-assistant.sshfs.host;
    path = "/homeassistant";
    extraOptions = [
      "IdentityFile=${config.services.home-assistant.sshfs.identityFile}"
      "IdentitiesOnly=yes"
      "StrictHostKeyChecking=no"
      "UserKnownHostsFile=/dev/null"
      "ServerAliveInterval=10"
    ];
  };
}
