{
  config,
  lib,
  pkgs,
  ...
}:

# NOTE to connect:
# sudo , xmrig -o xmrig-proxy.rofl-xx.nb.brkn.lol:8443 --tls --nicehash -p "$XMRIG_PROXY_PASSWORD" --rig-id "$HOSTNAME"

let
  cfg = config.services.xmrig-proxy;
  baseHostName = config.networking.hostName;
  inherit (config.domains) main netbird tailscale;
  p2poolStratum = "127.0.0.1:${toString config.services.p2pool.stratum.port}";
  useP2pool = cfg.targetPool == "p2pool";
  upstreamPool =
    if useP2pool then
      {
        url = p2poolStratum;
        user = "${config.networking.hostName}-proxy";
        tls = false;
      }
    else
      {
        url = "pool.hashvault.pro:443";
        user = config.sops.placeholder."xmrig-proxy/wallet";
        tls = true;
      };
  hostnames = [
    "xmrig-proxy.${baseHostName}.${netbird}"
    "xmrig-proxy.${baseHostName}.${tailscale}"
    "xmrig-proxy.${baseHostName}.${main}"
    "xp.${baseHostName}.${main}"
    "xp.${main}"
  ];
  hostname = builtins.head hostnames;
  extraHostnames = builtins.tail hostnames;
in
{
  options.services.xmrig-proxy.targetPool = lib.mkOption {
    type = lib.types.enum [
      "hashvault"
      "p2pool"
    ];
    default = "hashvault";
    description = "Upstream pool for xmrig-proxy to forward minerctl-managed miners to.";
  };

  config = {
    users = {
      groups.xmrigproxy = { };
      users.xmrigproxy = {
        isSystemUser = true;
        description = "XMRig Proxy service account";
        group = "xmrigproxy";
        home = "/var/lib/xmrig-proxy";
        shell = "/run/current-system/sw/bin/nologin";
      };
    };

    sops = {
      secrets = {
        "xmrig-proxy/password" = config.custom.mkSecret {
          restartUnits = [ "xmrig-proxy.service" ];
        };
      }
      // lib.optionalAttrs (!useP2pool) {
        "xmrig-proxy/wallet" = config.custom.mkSecret {
          restartUnits = [ "xmrig-proxy.service" ];
        };
      };

      # NOTE To interrogate the API:
      # curl http://127.0.0.1:9674/2/summary | jq
      # curl http://127.0.0.1:9674/1/workers | jq
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
            "api": {
              "id": "${config.networking.hostName}",
              "worker-id": "${config.networking.hostName}"
            },
            "http": {
              "enabled": true,
              "host": "127.0.0.1",
              "port": 9674,
              "access-token": null,
              "restricted": true
            },
            "pools": [{
              "coin": "monero",
              "url": "${upstreamPool.url}",
              "user": "${upstreamPool.user}",
              "pass": "${config.networking.hostName}",
              "tls": ${builtins.toJSON upstreamPool.tls},
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
        restartUnits = [ "xmrig-proxy.service" ];
      };
    };

    systemd.services.xmrig-proxy = {
      description = "XMRig-Proxy (Monero Stratum mining proxy)";
      wants = [ "network-online.target" ] ++ lib.optional useP2pool "p2pool.service";
      after = [ "network-online.target" ] ++ lib.optional useP2pool "p2pool.service";
      serviceConfig = {
        User = "xmrigproxy";
        Group = "xmrigproxy";

        # Block all - but our proxy
        # Below is too strict, miners will not be able to connect
        # IPAddressDeny = [ "any" ];

        # Block IPv6
        IPAddressDeny = [ "::/0" ];
        IPAddressAllow = [
          config.programs.proxychains.proxies.mullvad.host
          # cgnat (nb+ts)
          "100.64.0.0/10"
        ];

        ExecStart =
          if useP2pool then
            "${pkgs.xmrig-proxy}/bin/xmrig-proxy -c ${config.sops.templates.xmrigProxyConfig.path}"
          else
            "${pkgs.proxychains-ng}/bin/proxychains4 -f /etc/proxychains-tor.conf ${pkgs.xmrig-proxy}/bin/xmrig-proxy -c ${config.sops.templates.xmrigProxyConfig.path}";
        # Increase open file limit if expecting many connections
        LimitNOFILE = 65535;
        Restart = "on-failure";
      };
      # If a firewall is enabled, open port 3333 for miners:
      wantedBy = [ "multi-user.target" ];
    };

    networking.firewall.allowedTCPPorts = [
      3333
      8443
    ];

    services.nginx = {
      virtualHosts."${hostname}" = {
        serverAliases = extraHostnames;
        enableACME = true;
        # FIXME https://github.com/NixOS/nixpkgs/issues/210807
        acmeRoot = null;
        forceSSL = true;
      };

      streamConfig = ''
        upstream xmrig_backend {
          server 127.0.0.1:3333;
        }

        server {
          # TODO Multiplex on port 443
          listen 8443 ssl;

          ssl_certificate     ${config.users.users.acme.home}/${hostname}/fullchain.pem;
          ssl_certificate_key ${config.users.users.acme.home}/${hostname}/key.pem;

          proxy_pass xmrig_backend;

          # Prevent idle timeouts for hashing clients
          proxy_timeout          600s;
          proxy_connect_timeout  30s;
        }
      '';
    };
  };
}
