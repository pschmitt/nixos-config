{
  config,
  lib,
  pkgs,
  ...
}:
let
  monerodSyncCheck = pkgs.writeShellScript "monerod-sync-check" ''
    RPC_URL="http://127.0.0.1:${toString config.services.monero.rpc.port}/get_info"
    THRESHOLD_BP=9000

    INFO=$(${pkgs.curl}/bin/curl -sS --max-time 15 "$RPC_URL")

    LINE=$(
      echo "$INFO" | ${pkgs.jq}/bin/jq -er '
        if (.target_height // 0) > 0
        then
          ((.height * 10000) / .target_height | floor) as $bp
          | [$bp, (.height | tostring), (.target_height | tostring)]
          | @tsv
        else
          [-1, (.height | tostring), 0]
          | @tsv
        end
      '
    )

    IFS=$'\t' read -r SYNC_BP HEIGHT TARGET_HEIGHT <<< "$LINE"

    if [[ "$TARGET_HEIGHT" -gt 0 ]]
    then
      printf "sync=%d.%02d%% height=%s target=%s\n" \
        "$((SYNC_BP / 100))" \
        "$((SYNC_BP % 100))" \
        "$HEIGHT" \
        "$TARGET_HEIGHT"

      if [[ "$SYNC_BP" -lt "$THRESHOLD_BP" ]]
      then
        exit 1
      fi

      exit 0
    fi

    echo "sync=unknown height=''${HEIGHT:-0} target=''${TARGET_HEIGHT:-0}"
    exit 1
  '';
in
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

      check program "monerod sync" with path "${monerodSyncCheck}"
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

  networking.firewall.allowedTCPPorts = lib.mkAfter [ 18080 ];
}
