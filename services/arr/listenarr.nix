{ config, ... }:
let
  port = 4545;
  publicHost = "listen.arr.${config.domains.main}";
  dataDir = "/mnt/data/srv/listenarr/config";
  inherit (config.arr.dirs) audiobooks downloads;
  listenarrUser = "listenarr";
  listenarrGroup = listenarrUser;
in
{
  systemd.tmpfiles.rules = [
    "d ${dataDir} 0750 ${listenarrUser} ${listenarrGroup} - -"
    "d ${audiobooks} 0755 ${listenarrUser} ${listenarrGroup} - -"
    "d ${downloads}/listenarr 2770 ${config.services.transmission.user} ${listenarrGroup} - -"
  ];

  users.groups.${listenarrGroup} = { };
  users.users.${listenarrUser} = {
    isSystemUser = true;
    group = listenarrGroup;
    extraGroups = [ config.services.transmission.group ];
  };

  virtualisation.oci-containers.containers.listenarr = {
    image = "ghcr.io/therobbiedavis/listenarr:canary";
    autoStart = true;
    pull = "always";
    user = "${toString config.users.users.${listenarrUser}.uid}:${
      toString config.users.groups.${listenarrGroup}.gid
    }";
    environment = {
      LISTENARR_PUBLIC_URL = "https://${publicHost}";
    };
    volumes = [
      "${dataDir}:/app/config"
      "${downloads}:${downloads}"
      "${audiobooks}:${audiobooks}"
    ];
    extraOptions = [
      "--net=ns:/run/netns/mullvad"
    ];
  };

  arr.services.listenarr = {
    inherit port;
    host = publicHost;
    container = "listenarr";
  };
}
