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
    optionalString
    escapeShellArgs
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

      walletFromSops = cfg.walletSecret != null && cfg.sopsFile != null;

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
      ++ cfg.extraArgs;

      exec =
        if walletFromSops then
          # Use env file with WALLET=... to avoid putting the address in the unit
          "${cfg.package}/bin/p2pool --wallet $WALLET ${escapeShellArgs commonArgs}"
        else
          "${cfg.package}/bin/p2pool --wallet ${
            escapeShellArgs [ (cfg.walletAddress or "") ]
          } ${escapeShellArgs commonArgs}";
    in
    mkIf cfg.enable {
      assertions = [
        {
          assertion = walletFromSops || (cfg.walletAddress != null);
          message = "services.p2pool: set walletAddress OR walletSecret+sopsFile.";
        }
      ];

      users.groups.${cfg.group} = { };
      users.users.${cfg.user} = {
        isSystemUser = true;
        group = cfg.group;
        home = cfg.dataDir;
        createHome = true;
      };

      # If SOPS is used, create a tiny env file with WALLET=...
      # (keeps the address out of the ExecStart line)
      sops.secrets = lib.mkIf walletFromSops {
        "${cfg.walletSecret}" = {
          sopsFile = cfg.sopsFile;
          restartUnits = [ "p2pool.service" ];
          owner = cfg.user;
          group = cfg.group;
        };
      };

      sops.templates = lib.mkIf walletFromSops {
        p2poolEnv = {
          # systemd EnvironmentFile needs KEY=VALUE syntax
          content = ''
            WALLET=${config.sops.placeholder."${cfg.walletSecret}"}
          '';
          restartUnits = [ "p2pool.service" ];
        };
      };

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
          EnvironmentFile = lib.mkIf walletFromSops config.sops.templates.p2poolEnv.path;

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
    };
}
