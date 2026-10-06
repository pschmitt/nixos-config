{ config, ... }:
let
  browserlessHosts = config.domains.meshHosts "browserless";
  steelHosts = config.domains.meshHosts "steel";
  autheliaConfig = import ./authelia-nginx-config.nix {
    inherit config;
    haIngressBypass = false;
  };

  browserVhost = port: hosts: rewriteSteelEndpoint: {
    ${builtins.head hosts} = {
      serverAliases = builtins.tail hosts;
      enableACME = true;
      acmeRoot = null;
      forceSSL = true;
      extraConfig = autheliaConfig.server;

      locations = {
        "/" = {
          proxyPass = "http://127.0.0.1:${toString port}";
          proxyWebsockets = true;
          recommendedProxySettings = true;
          extraConfig =
            autheliaConfig.location
            + ''
              proxy_read_timeout 3600s;
              proxy_send_timeout 3600s;
            ''
            + (
              if rewriteSteelEndpoint then
                ''
                  # Steel advertises its internal loopback address in UI session responses.
                  # Rewrite it to the hostname the browser used, including the TLS scheme.
                  proxy_set_header Accept-Encoding "";
                  sub_filter_types application/json text/html;
                  sub_filter_once off;
                  sub_filter "ws://127.0.0.1:3002" "wss://$http_host";
                  sub_filter "http://127.0.0.1:3002" "https://$http_host";
                  proxy_redirect ~^http://127\.0\.0\.1:3003/devtools/devtools_app\.html\?ws=//127\.0\.0\.1:3003(/.*)$ https://$http_host/devtools/devtools_app.html?ws=//$http_host$1;
                ''
              else
                ""
            );
        };
      }
      // (
        if rewriteSteelEndpoint then
          {
            "/devtools/" = {
              proxyPass = "http://127.0.0.1:3003";
              proxyWebsockets = true;
              recommendedProxySettings = true;
              extraConfig = autheliaConfig.location + ''
                proxy_read_timeout 3600s;
                proxy_send_timeout 3600s;
              '';
            };
          }
        else
          { }
      );
    };
  };
in
{
  services.nginx.virtualHosts =
    (browserVhost 3001 browserlessHosts false) // (browserVhost 3002 steelHosts true);
}
