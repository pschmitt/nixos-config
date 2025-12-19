{
  config,
  lib,
  pkgs,
  ...
}:

# NOTE To quickly load the blockchain, consider this bootstrap procedure:
# wget https://downloads.getmonero.org/blockchain.raw
# sudo systemctl stop monero.service monit.service
# sudo -u monero monero-blockchain-import --input-file blockchain.raw --data-dir /var/lib/monero
# sudo systemctl start monero.service monit.service

let
  monerodSyncStatusImpl = pkgs.writeShellScript "monerod-sync-status-impl" (
    builtins.readFile ./monerod-sync-status.sh
  );
  monerodSyncStatus = pkgs.writeShellScriptBin "monerod-sync-status" ''
    set -euo pipefail

    export PATH="${
      lib.makeBinPath [
        pkgs.bash
        pkgs.coreutils
        pkgs.curl
        pkgs.jq
      ]
    }"
    export MONEROD_RPC_URL_DEFAULT="http://127.0.0.1:${toString config.services.monero.rpc.port}/get_info"
    export MONEROD_THRESHOLD_BP_DEFAULT="9000"
    export MONEROD_RPC_USERNAME_FILE_DEFAULT="${config.sops.secrets."monerod/rpc/username".path}"
    export MONEROD_RPC_PASSWORD_FILE_DEFAULT="${config.sops.secrets."monerod/rpc/password".path}"

    exec ${monerodSyncStatusImpl} "$@"
  '';
in
{
  sops = {
    secrets = {
      "monerod/rpc/username".sopsFile = config.custom.sopsFile;
      "monerod/rpc/password".sopsFile = config.custom.sopsFile;
    };

    templates."monerod/rpc.env" = {
      content = ''
        MONEROD_RPC_USERNAME=${config.sops.placeholder."monerod/rpc/username"}
        MONEROD_RPC_PASSWORD=${config.sops.placeholder."monerod/rpc/password"}
      '';
      owner = "monero";
      group = "monero";
      mode = "0400";
      restartUnits = [
        "monero.service"
      ];
    };
  };

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
        user = "$MONEROD_RPC_USERNAME";
        password = "$MONEROD_RPC_PASSWORD";
      };
      mining = {
        enable = false;
        threads = 0;
        address = "";
      };
    };

    tor.relay.onionServices = {
      "monerod/p2p" = {
        map = [
          {
            port = 18080;
            target = {
              addr = "127.0.0.1";
              port = 18080;
            };
          }
        ];
      };
      "monerod/rpc" =
        let
          inherit (config.services.monero) rpc;
        in
        {
          map = [
            {
              inherit (rpc) port;
              target = {
                addr = rpc.address;
                inherit (rpc) port;
              };
            }
          ];
        };
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

      check program "monerod sync" with path "${monerodSyncStatus}/bin/monerod-sync-status"
        group monero
        group services
        if status > 0 then alert
    '';

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

    restic.backups.main.exclude = [ config.users.users.monero.home ];
  };

  services.monero.environmentFile = config.sops.templates."monerod/rpc.env".path;

  environment.systemPackages = lib.mkAfter [ monerodSyncStatus ];

  networking.firewall.allowedTCPPorts = lib.mkAfter [ 18080 ];
}
