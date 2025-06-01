{ config, pkgs, ... }:

{
  users.groups.xmrigproxy = { };
  users.users.xmrigproxy = {
    isSystemUser = true;
    description = "XMRig Proxy service account";
    group = "xmrigproxy";
    home = "/var/lib/xmrig-proxy";
    shell = "/run/current-system/sw/bin/nologin";
  };

  sops = {
    secrets = {
      "xmrig-proxy/wallet" = {
        sopsFile = config.custom.sopsFile;
        restartUnits = [ "xmrig-proxy.service" ];
      };
      "xmrig-proxy/password" = {
        sopsFile = config.custom.sopsFile;
        restartUnits = [ "xmrig-proxy.service" ];
      };
    };

    templates.xmrigProxyConfig = {
      content = ''
        {
          "access-log-file": null,
          "access-password": "${config.sops.placeholder."xmrig-proxy/password"}",
          "mode": "nicehash",
          "donate-level": 0,
          "bind": [{
            "host": "0.0.0.0",
            "port": 3333,
            "tls": false
          }],
          "pools": [{
            "coin": "monero",
            "url": "pool.hashvault.pro:443",
            "user": "${config.sops.placeholder."xmrig-proxy/wallet"}",
            "pass": "${config.networking.hostName}",
            "tls": true,
            "keepalive": true
          }],
          "retries": 5,
          "retry-pause": 5,
          "verbose": false,
          "workers": true
        }
      '';

      owner = "xmrigproxy";
      group = "xmrigproxy";
    };
  };

  systemd.services.xmrig-proxy = {
    description = "XMRig-Proxy (Monero Stratum mining proxy)";
    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];
    serviceConfig = {
      User = "xmrigproxy";
      Group = "xmrigproxy";
      ExecStart = "${pkgs.xmrig-proxy}/bin/xmrig-proxy -c ${config.sops.templates.xmrigProxyConfig.path}";
      # Increase open file limit if expecting many connections
      LimitNOFILE = 65535;
      Restart = "on-failure";
    };
    # If a firewall is enabled, open port 3333 for miners:
    wantedBy = [ "multi-user.target" ];
  };

  networking.firewall.allowedTCPPorts = [ 3333 ];

  services.nginx = {
    virtualHosts."xmrig-proxy.${config.networking.hostName}.nb.${config.custom.mainDomain}" = {
      enableACME = true;
      forceSSL = true;
    };

    streamConfig = ''
      upstream xmrig_backend {
        server 127.0.0.1:3333;
      }

      server {
        # TODO Multiplex on port 443
        listen 8443 ssl;

        ssl_certificate     /var/lib/acme/xmrig-proxy.${config.networking.hostName}.nb.${config.custom.mainDomain}/fullchain.pem;
        ssl_certificate_key /var/lib/acme/xmrig-proxy.${config.networking.hostName}.nb.${config.custom.mainDomain}/key.pem;

        proxy_pass xmrig_backend;

        # Prevent idle timeouts for hashing clients
        proxy_timeout          600s;
        proxy_connect_timeout  30s;
      }
    '';
  };
}
