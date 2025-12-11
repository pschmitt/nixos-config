{
  config,
  lib,
  pkgs,
  ...
}:
{
  # sops.secrets = {
  #   "monerod/htpasswd" = {
  #     owner = "nginx";
  #   };
  # };

  services = {
    monero = {
      enable = true;
      # https://docs.getmonero.org/interacting/monero-config-file/#monerodconf
      extraConfig = ''
        check-updates=disabled
        enable-dns-blocklist=1

        # Optional pruning
        prune-blockchain=1
        sync-pruned-blocks=1
      '';
      rpc = {
        address = "127.0.0.1";
        port = 18081;
        restricted = false;
        # user = "fart";
        # password = "fart";
      };
      mining = {
        enable = false;
        threads = 0;
        address = "";
      };
    };

    nginx =
      let
        # TODO add a public endpoint, with basic auth?
        hostNames = [
          # public
          # "xmr.${config.domains.main}"
          # vpn
          "xmr.${config.networking.hostName}.${config.domains.netbird}"
          "xmr.${config.networking.hostName}.${config.domains.tailscale}"
        ];
        virtualHosts = builtins.listToAttrs (
          map (hostName: {
            name = hostName;
            value = {
              enableACME = true;
              # FIXME https://github.com/NixOS/nixpkgs/issues/210807
              acmeRoot = null;
              forceSSL = false;
              locations."/" = {
                proxyPass = "http://${config.services.monero.rpc.address}:${toString config.services.monero.rpc.port}";
                recommendedProxySettings = true;
                proxyWebsockets = true;
              };
              # FIXME basic auth does not work
              # with monero-wallet-cli --daemon-login
              # basicAuthFile = config.sops.secrets."monerod/htpasswd".path;
            };
          }) hostNames
        );
      in
      {
        inherit virtualHosts;
      };

    monit.config = lib.mkAfter ''
      check host "monerod" with address "127.0.0.1"
        group services
        restart program = "${pkgs.systemd}/bin/systemctl restart monerod"
        if failed
          port ${toString config.services.monero.rpc.port}
          type tcp
          with timeout 15 seconds
        then restart
        if 5 restarts within 10 cycles then alert
    '';
  };

  networking.firewall.allowedTCPPorts = lib.mkAfter [ 18080 ];
}
