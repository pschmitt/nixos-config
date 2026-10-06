{
  config,
  ...
}:
let
  hosts = config.domains.meshHosts "steel";
  dataDir = "/var/lib/steel";
  autheliaConfig = import "../authelia-nginx-config.nix" {
    inherit config;
    haIngressBypass = false;
  };
in
{
  systemd.tmpfiles.rules = [ "d ${dataDir} 0700 root root - -" ];

  virtualisation.oci-containers.containers.steel = {
    image = "ghcr.io/steel-dev/steel-browser@sha256:d8e93f8a6f847c3e1cc1dc1269446bc99e8123baccc5e5cc2df052c2b7aa5c16";
    autoStart = true;
    log-driver = "none";
    ports = [
      "127.0.0.1:3002:3000"
      "127.0.0.1:3003:9223"
    ];
    volumes = [ "${dataDir}:/app/.cache" ];
    environment = {
      DOMAIN = "127.0.0.1:3002";
      CDP_DOMAIN = "127.0.0.1:3003";
    };
    extraOptions = [
      "--init"
      "--shm-size=2g"
    ];
  };

  services.nginx.virtualHosts.${builtins.head hosts} = {
    serverAliases = builtins.tail hosts;
    enableACME = true;
    acmeRoot = null;
    forceSSL = true;
    extraConfig = autheliaConfig.server;

    locations = {
      "/" = {
        proxyPass = "http://127.0.0.1:3002";
        proxyWebsockets = true;
        recommendedProxySettings = false;
        extraConfig = autheliaConfig.location + ''
          proxy_read_timeout 3600s;
          proxy_send_timeout 3600s;

          # Steel advertises its internal loopback address in UI session responses.
          # Rewrite it to the hostname the browser used, including the TLS scheme.
          # Its WebSocket handler rejects public Host values, so send a local Host
          # upstream and preserve the original hostname in forwarding headers.
          proxy_set_header Host localhost:3002;
          proxy_set_header X-Real-IP $remote_addr;
          proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
          proxy_set_header X-Forwarded-Host $http_host;
          proxy_set_header X-Forwarded-Proto $scheme;
          proxy_set_header Accept-Encoding "";
          sub_filter_types application/json text/html;
          sub_filter_once off;
          sub_filter "ws://127.0.0.1:3002" "wss://$http_host";
          sub_filter "http://127.0.0.1:3002" "https://$http_host";
          proxy_redirect ~^http://127\.0\.0\.1:3003/devtools/devtools_app\.html\?ws=//127\.0\.0\.1:3003(/.*)$ https://$http_host/devtools/devtools_app.html?ws=//$http_host$1;
        '';
      };

      "/devtools/" = {
        proxyPass = "http://127.0.0.1:3003";
        proxyWebsockets = true;
        recommendedProxySettings = false;
        extraConfig = autheliaConfig.location + ''
          proxy_read_timeout 3600s;
          proxy_send_timeout 3600s;

          # Chromium only accepts DevTools connections with a local Host header.
          proxy_set_header Host localhost:3003;
          proxy_set_header X-Real-IP $remote_addr;
          proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
          proxy_set_header X-Forwarded-Host $http_host;
          proxy_set_header X-Forwarded-Proto $scheme;
        '';
      };
    };
  };
}
