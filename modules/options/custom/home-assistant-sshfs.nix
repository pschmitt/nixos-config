{ config, lib, ... }:
{
  options.custom.homeAssistant.sshfs.identityFile = lib.mkOption {
    type = lib.types.path;
    default = "${config.mainUser.homeDirectory}/.ssh/id_ed25519";
    description = ''
      SSH private key used to mount the Home Assistant config repo
      (/mnt/ha). Defaults to the main user's personal key (workstations);
      hosts without that key on disk (servers) should point this at a
      dedicated key instead.
    '';
  };

  options.custom.homeAssistant.sshfs.host = lib.mkOption {
    type = lib.types.str;
    default = "hass.${config.domains.vpn}";
    description = "SSH host serving the Home Assistant configuration mount.";
  };
}
