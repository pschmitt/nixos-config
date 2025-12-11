{ config, pkgs, ... }:
let
  internalIP = config.vpnNamespaces.mullvad.namespaceAddress;
  port = 5000;
  publicHost = "listen.arr.${config.domains.main}";
  autheliaConfig = import ../authelia-nginx-config.nix { inherit config; };
  containerService = config.virtualisation.oci-containers.containers.listenarr.serviceName;
  dataDir = "/mnt/data/srv/listenarr/config";
  transmissionDownloadDir =
    config.services.transmission.settings."download-dir"
      or "${config.services.transmission.home}/Downloads";
  audiobooksDir = "/mnt/data/audiobooks";
  listenarrUser = "listenarr";
  listenarrGroup = listenarrUser;
in
{
  systemd.tmpfiles.rules = [
    "d ${dataDir} 0750 ${listenarrUser} ${listenarrGroup} - -"
    "d ${audiobooksDir} 0755 ${listenarrUser} ${listenarrGroup} - -"
    "d ${transmissionDownloadDir}/listenarr 2770 ${config.services.transmission.user} ${listenarrGroup} - -"
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
      "${transmissionDownloadDir}:${transmissionDownloadDir}"
      "${audiobooksDir}:${audiobooksDir}"
    ];
    extraOptions = [
      "--net=ns:/run/netns/mullvad"
    ];
  };

  vpnNamespaces.mullvad.portMappings = [
    {
      from = port;
      to = port;
    }
  ];

  systemd.services."${containerService}" = {
    wantedBy = [ "arr.target" ];
    partOf = [ "arr.target" ];
    after = [ "mullvad.service" ];
    requires = [ "mullvad.service" ];
  };

  services = {
    nginx.virtualHosts."${publicHost}" = {
      enableACME = true;
      # FIXME https://github.com/NixOS/nixpkgs/issues/210807
      acmeRoot = null;
      forceSSL = true;
      extraConfig = autheliaConfig.server;
      locations."/" = {
        proxyPass = "http://${internalIP}:${toString port}";
        proxyWebsockets = true;
        recommendedProxySettings = true;
        extraConfig = autheliaConfig.location;
      };
    };

    monit.config = ''
      check host "listenarr" with address ${internalIP}
        group piracy
        depends on mullvad-netns
        restart program = "${pkgs.systemd}/bin/systemctl restart ${containerService}"
        if failed port ${toString port} protocol http for 3 cycles then restart
        if 2 restarts within 10 cycles then alert
    '';
  };

  fakeHosts.listenarr.port = port;
}
