{
  config,
  lib,
  pkgs,
  ...
}:
let
  internalIP = config.vpnNamespaces.mullvad.namespaceAddress;
  port = 9091;
  publicHost = "to.arr.${config.domains.main}";
  serverAliases = [ "to.${config.domains.main}" ];
  autheliaConfig = import ../authelia-nginx-config.nix { inherit config; };
  downloadDir =
    config.services.transmission.settings."download-dir"
      or "${config.services.transmission.home}/Downloads";
in
{
  sops = {
    secrets = {
      "transmission/username" = {
        inherit (config.custom) sopsFile;
        owner = config.services.transmission.user;
        inherit (config.services.transmission) group;
      };
      "transmission/password" = {
        inherit (config.custom) sopsFile;
        owner = config.services.transmission.user;
        inherit (config.services.transmission) group;
      };
    };

    templates."transmission-credentials.json" = {
      content = ''
        {
          "rpc-username": "${config.sops.placeholder."transmission/username"}",
          "rpc-password": "${config.sops.placeholder."transmission/password"}"
        }
      '';
      owner = config.services.transmission.user;
      inherit (config.services.transmission) group;
    };
  };

  systemd.tmpfiles.rules = [
    "d ${downloadDir} 2775 ${config.services.transmission.user} ${config.services.transmission.group} - -"
  ];

  services = {
    transmission = {
      enable = true;
      package = pkgs.transmission_4;
      credentialsFile = config.sops.templates."transmission-credentials.json".path;
      settings = {
        rpc-bind-address = internalIP;
        rpc-whitelist-enabled = false;
        rpc-host-whitelist-enabled = false;
        rpc-authentication-required = true;
        ratio-limit = 0;
        ratio-limit-enabled = true;
        umask = 2;
      };
    };

    nginx.virtualHosts."${publicHost}" = {
      inherit serverAliases;
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
      check host "transmission" with address ${internalIP}
        group piracy
        depends on mullvad-netns
        restart program = "${pkgs.systemd}/bin/systemctl restart transmission"
        if failed port ${toString port} protocol http status 401 then restart
        if 5 restarts within 5 cycles then alert
    '';
  };

  fakeHosts.transmission.port = port;

  # add main user to transmission group
  users.users."${config.mainUser.username}".extraGroups = [ config.services.transmission.group ];

  systemd.services.transmission = {
    wantedBy = [ "arr.target" ];
    partOf = [ "arr.target" ];
    vpnConfinement = {
      enable = true;
      vpnNamespace = "mullvad";
    };
    # Fix for systemd-resolved atomic updates breaking bind mounts
    serviceConfig.TemporaryFileSystem = "/run/systemd/resolve";

    serviceConfig = {
      # Fuck ipv6, all my homies use ipv4
      IPAddressDeny = lib.mkForce [ "::/0" ];
      RestrictAddressFamilies = lib.mkForce [
        "AF_UNIX"
        "AF_INET"
      ];
    };
  };

  vpnNamespaces.mullvad.portMappings = [
    {
      from = port;
      to = port;
    }
  ];
}
