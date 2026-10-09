{ config, lib, ... }:
let
  # Home Assistant lives under /srv/hass here, not the /mnt/ha mount the
  # shared defaults (home-manager/cli/zsh/config/directories.nix) point at.
  hass = "/srv/hass";
  directories = {
    inherit hass;
    ha = hass;
    home-assistant = hass;
    homeassistant = hass;
    hass-config = "${hass}/config/hass";
    zbx = "/srv/zabbix";
    zbx-ag = "/srv/zabbix-agent2";
  };
in
{
  home-manager.users.${config.mainUser.username}.programs.zsh = {
    dirHashes = directories;
    shellAliases = lib.mapAttrs' (
      name: dir: lib.nameValuePair "cd${name}" "cd ${lib.escapeShellArg dir}"
    ) directories;
    sessionVariables = {
      host_alias = "fnc";
      NETWORK_LOCATION = "home";
      NO_LOCATION_UPDATE = "1";
      SERVER = "1";
    };
  };
}
