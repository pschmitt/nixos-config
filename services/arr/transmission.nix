{
  config,
  lib,
  pkgs,
  ...
}:
let
  internalIP = config.vpnNamespaces.mullvad.namespaceAddress;
  port = 9091;
  publicHost = "to.arr.${config.custom.mainDomain}";
  serverAliases = [ "to.${config.custom.mainDomain}" ];
  autheliaConfig = import ./authelia.nix { inherit config; };
  downloadDir =
    config.services.transmission.settings."download-dir"
      or "${config.services.transmission.home}/Downloads";
in
{
  sops = {
    secrets = {
      "transmission/username" = {
        inherit (config.custom) sopsFile;
        owner = "transmission";
        group = "transmission";
      };
      "transmission/password" = {
        inherit (config.custom) sopsFile;
        owner = "transmission";
        group = "transmission";
      };
    };

    templates."transmission-credentials.json" = {
      content = ''
        {
          "rpc-username": "${config.sops.placeholder."transmission/username"}",
          "rpc-password": "${config.sops.placeholder."transmission/password"}"
        }
      '';
      owner = "transmission";
      group = "transmission";
    };
  };

  users.users.transmission.extraGroups = [ "media" ];

  systemd.tmpfiles.rules = [
    "d ${downloadDir} 2775 transmission media - -"
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

  systemd.services.transmission = {
    vpnConfinement = {
      enable = true;
      vpnNamespace = "mullvad";
    };
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
