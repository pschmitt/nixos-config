{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib)
    mkOption
    mkEnableOption
    types
    mkIf
    escapeShellArgs
    mkMerge
    ;
in
{
  options.services.p2pool = {
    enable = mkEnableOption "Monero p2pool";

    package = mkOption {
      type = types.package;
      default = pkgs.p2pool;
      description = "p2pool package to run.";
    };

    # Either set walletAddress OR set both walletSecret + sopsFile.
    walletAddress = mkOption {
      type = types.nullOr types.str;
      default = null;
      example = "44Affq5kSiGBoZ...";
      description = "Primary XMR address to mine to (NOT a subaddress).";
    };

    walletSecret = mkOption {
      type = types.nullOr types.str;
      default = null;
      example = "p2pool/wallet/address";
      description = "SOPS secret name that contains the wallet address (plain string).";
    };

    sopsFile = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = "SOPS file to read walletSecret from.";
    };

    dataDir = mkOption {
      type = types.path;
      default = "/var/lib/p2pool";
      description = "State directory for p2pool.";
    };

    user = mkOption {
      type = types.str;
      default = "p2pool";
    };
    group = mkOption {
      type = types.str;
      default = "p2pool";
    };

    moneroRpcAddress = mkOption {
      type = types.str;
      default = "127.0.0.1";
    };
    moneroRpcPort = mkOption {
      type = types.port;
      default = 18081;
    };
    zmqPort = mkOption {
      type = types.port;
      default = 18083;
    };

    mode = mkOption {
      type = types.enum [
        "standard"
        "mini"
        "nano"
      ];
      default = "mini";
      description = "Sidechain size preset.";
    };

    stratum.bindAddress = mkOption {
      type = types.str;
      default = "0.0.0.0";
    };
    stratum.port = mkOption {
      type = types.port;
      default = 3333;
    };

    # Leave null to use mode-dependent default (std=37889, mini=37888, nano=37890)
    p2p.bindAddress = mkOption {
      type = types.str;
      default = "0.0.0.0";
    };
    p2p.port = mkOption {
      type = types.nullOr types.port;
      default = null;
    };

    addPeers = mkOption {
      type = types.listOf types.str;
      default = [ ];
      example = [
        "peer1.example:37889"
        "1.2.3.4:37890"
      ];
      description = "Optional additional peers.";
    };

    openFirewall = mkOption {
      type = types.bool;
      default = false;
    };

    dataApi = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Expose p2pool's JSON data API through generated files.";
      };

      path = mkOption {
        type = types.path;
        default = "${config.services.p2pool.dataDir}/api";
        description = "Directory where p2pool writes JSON data API files.";
      };

      exposeNginx = mkOption {
        type = types.bool;
        default = true;
        description = "Serve selected p2pool JSON data API files via the xmr nginx vhosts.";
      };

      urlPrefix = mkOption {
        type = types.str;
        default = "/p2pool";
        description = "URL prefix used when exposing selected p2pool API files via nginx.";
      };

      hostNames = mkOption {
        type = types.listOf types.str;
        default = [
          "xmr.${config.networking.hostName}.${config.domains.netbird}"
          "xmr.${config.networking.hostName}.${config.domains.tailscale}"
        ];
        description = "Nginx virtual hosts that should expose selected p2pool API files.";
      };
    };

    extraArgs = mkOption {
      type = types.listOf types.str;
      default = [ ];
      example = [
        "--out-peers"
        "64"
        "--loglevel"
        "2"
      ];
    };
  };

  config =
    let
      cfg = config.services.p2pool;

      modeFlag =
        if cfg.mode == "standard" then
          [ ]
        else if cfg.mode == "mini" then
          [ "--mini" ]
        else
          [ "--nano" ];

      defaultP2pPort =
        if cfg.mode == "standard" then
          37889
        else if cfg.mode == "mini" then
          37888
        else
          37890;

      effectiveP2pPort = if cfg.p2p.port != null then cfg.p2p.port else defaultP2pPort;

      stratumSpec = "${cfg.stratum.bindAddress}:${toString cfg.stratum.port}";
      p2pSpec = "${cfg.p2p.bindAddress}:${toString effectiveP2pPort}";
      dataApiPath = toString cfg.dataApi.path;
      dataApiPrefix = lib.removeSuffix "/" cfg.dataApi.urlPrefix;

      walletFromSops = cfg.walletSecret != null && cfg.sopsFile != null;

      moneroRpcSecretsAvailable =
        (config ? sops)
        && (config.sops ? secrets)
        && (lib.hasAttr "monerod/rpc/username" config.sops.secrets)
        && (lib.hasAttr "monerod/rpc/password" config.sops.secrets);

      commonArgs = [
        "--host"
        cfg.moneroRpcAddress
        "--rpc-port"
        (toString cfg.moneroRpcPort)
        "--zmq-port"
        (toString cfg.zmqPort)
        "--stratum"
        stratumSpec
        "--p2p"
        p2pSpec
      ]
      ++ (lib.concatMap (p: [
        "--addpeers"
        p
      ]) cfg.addPeers)
      ++ modeFlag
      ++ lib.optionals cfg.dataApi.enable [
        "--data-api"
        dataApiPath
        "--local-api"
      ]
      ++ cfg.extraArgs;

      commonArgsEscaped = escapeShellArgs commonArgs;

      rpcLoginArg = lib.optionalString moneroRpcSecretsAvailable "--rpc-login \${MONEROD_RPC_USERNAME}:\${MONEROD_RPC_PASSWORD}";

      exec =
        if walletFromSops then
          # Use env file with WALLET=... to avoid putting the address in the unit
          "${cfg.package}/bin/p2pool --wallet $WALLET ${commonArgsEscaped} ${rpcLoginArg}"
        else
          "${cfg.package}/bin/p2pool --wallet ${
            lib.escapeShellArg (cfg.walletAddress or "")
          } ${commonArgsEscaped} ${rpcLoginArg}";
    in
    mkIf cfg.enable (mkMerge [
      {
        assertions = [
          {
            assertion = walletFromSops || (cfg.walletAddress != null);
            message = "services.p2pool: set walletAddress OR walletSecret+sopsFile.";
          }
        ];

        users.groups.${cfg.group} = { };
        users.users.${cfg.user} = {
          inherit (cfg) group;
          isSystemUser = true;
          home = cfg.dataDir;
          createHome = true;
        };

        # If SOPS is used, create a tiny env file (WALLET=..., MONEROD_RPC_*).
        sops = lib.mkIf (walletFromSops || moneroRpcSecretsAvailable) {
          secrets = lib.mkIf walletFromSops {
            "${cfg.walletSecret}" = {
              inherit (cfg) sopsFile group;
              restartUnits = [ "p2pool.service" ];
              owner = cfg.user;
            };
          };

          templates.p2poolEnv = {
            owner = cfg.user;
            inherit (cfg) group;
            mode = "0400";
            content = ''
              ${lib.optionalString walletFromSops ''
                WALLET=${config.sops.placeholder."${cfg.walletSecret}"}
              ''}
              ${lib.optionalString moneroRpcSecretsAvailable ''
                MONEROD_RPC_USERNAME=${config.sops.placeholder."monerod/rpc/username"}
                MONEROD_RPC_PASSWORD=${config.sops.placeholder."monerod/rpc/password"}
              ''}
            '';
            restartUnits = [ "p2pool.service" ];
          };
        };

        services.monero.extraConfig = ''
          # add for p2pool's quick template updates
          zmq-pub=tcp://127.0.0.1:${toString cfg.zmqPort}
        '';

        systemd.services.p2pool = {
          description = "Monero p2pool";
          after = [ "network-online.target" ];
          wants = [ "network-online.target" ];
          environment = lib.mkIf (!walletFromSops) { };
          serviceConfig = {
            User = cfg.user;
            Group = cfg.group;
            StateDirectory = "p2pool";
            WorkingDirectory = cfg.dataDir;
            ExecStart = exec;
            ExecStartPre = lib.mkIf cfg.dataApi.enable "${pkgs.coreutils}/bin/install -d -o ${cfg.user} -g ${cfg.group} -m 0755 ${dataApiPath}";
            EnvironmentFile = lib.mkIf (
              walletFromSops || moneroRpcSecretsAvailable
            ) config.sops.templates.p2poolEnv.path;

            Restart = "on-failure";
            RestartSec = 5;

            # Hardening
            NoNewPrivileges = true;
            PrivateTmp = true;
            ProtectHome = true;
            ProtectSystem = "strict";
            ReadWritePaths = [ cfg.dataDir ];
            CapabilityBoundingSet = "";
            AmbientCapabilities = "";
            LockPersonality = true;
          };
          wantedBy = [ "multi-user.target" ];
        };

        networking.firewall.allowedTCPPorts = lib.mkIf cfg.openFirewall [
          cfg.stratum.port
          effectiveP2pPort
        ];
      }
      (mkIf (cfg.dataApi.enable && cfg.dataApi.exposeNginx) {
        users.users.nginx.extraGroups = [ cfg.group ];
        services.nginx.virtualHosts = lib.genAttrs cfg.dataApi.hostNames (_: {
          locations = {
            "${dataApiPrefix}/".return = "404";
            "= ${dataApiPrefix}/network/stats".alias = "${dataApiPath}/network/stats";
            "= ${dataApiPrefix}/pool/stats".alias = "${dataApiPath}/pool/stats";
            "= ${dataApiPrefix}/stats_mod".alias = "${dataApiPath}/stats_mod";
            "= ${dataApiPrefix}/local/stratum".alias = "${dataApiPath}/local/stratum";
            "= ${dataApiPrefix}/local/p2p".alias = "${dataApiPath}/local/p2p";
          };
        });
      })
    ]);
}
