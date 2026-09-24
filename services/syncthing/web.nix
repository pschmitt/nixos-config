{
  config,
  lib,
  pkgs,
  ...
}:
let
  meshHosts = config.domains.meshHosts "syncthing";
  primaryHost = builtins.head meshHosts;
  directUiDrop = "! -i lo -p tcp --dport 8384 -j DROP";
  iptables = "${pkgs.iptables}/bin/iptables";
  ip6tables = "${pkgs.iptables}/bin/ip6tables";
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

  networking.firewall.extraInputRules = lib.mkIf (
    config.networking.firewall.enable && config.networking.firewall.backend == "nftables"
  ) "tcp dport 8384 drop";

  networking.firewall.extraCommands =
    lib.mkIf (config.networking.firewall.enable && config.networking.firewall.backend == "iptables")
      ''
        iptables -w -I nixos-fw 1 ${directUiDrop}
        ip6tables -w -I nixos-fw 1 ${directUiDrop}
      '';

  # lrz deliberately disables the NixOS firewall. Install only this narrow
  # INPUT rule there, leaving its other host networking behavior untouched.
  systemd.services.syncthing-firewall = lib.mkIf (!config.networking.firewall.enable) {
    description = "Block direct access to the Syncthing GUI";
    wantedBy = [ "multi-user.target" ];
    after = [ "network-pre.target" ];
    before = [ "network.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = [
        "${iptables} -w -I INPUT 1 ! -i lo -p tcp --dport 8384 -j DROP"
        "${ip6tables} -w -I INPUT 1 ! -i lo -p tcp --dport 8384 -j DROP"
      ];
      ExecStop = [
        "-${iptables} -w -D INPUT ! -i lo -p tcp --dport 8384 -j DROP"
        "-${ip6tables} -w -D INPUT ! -i lo -p tcp --dport 8384 -j DROP"
      ];
    };
  };
}
