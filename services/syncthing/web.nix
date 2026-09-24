{ config, ... }:
let
  meshHosts = config.domains.meshHosts "syncthing";
  primaryHost = builtins.head meshHosts;
  autheliaConfig = import ../authelia-nginx-config.nix {
    inherit config;
    haIngressBypass = false;
  };
in
{
  imports = [ ../http.nix ];

  services.syncthing.settings.gui = {
    address = "127.0.0.1:8384";
    insecureSkipHostcheck = true;
  };

  services.nginx.virtualHosts.${primaryHost} = {
    serverAliases = builtins.tail meshHosts;
    enableACME = true;
    acmeRoot = null;
    forceSSL = true;
    extraConfig = autheliaConfig.server;

    locations."/" = {
      proxyPass = "http://127.0.0.1:8384";
      proxyWebsockets = true;
      recommendedProxySettings = true;
      extraConfig = autheliaConfig.location;
    };
  };

  networking.firewall = {
    # Keep the GUI loopback-only; reach it remotely through the authenticated
    # mesh vhosts above. This also blocks accidental future listeners on 8384.
    extraInputRules = "tcp dport 8384 drop";
  };
}
