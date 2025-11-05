{
  config,
  lib,
  pkgs,
  ...
}:
let
  monerodAddr = "http://${config.services.monero.rpc.address}:${toString config.services.monero.rpc.port}";

  walletRpcBindPort = 18084;
  walletHostDir = "/mnt/data/srv/monerod/data/monero-wallet-rpc";
  walletFile = "${walletHostDir}/wallet/xmrig-wallet";
  walletRpcConfigFile = config.sops.templates.moneroWalletRpcConfig.path;

  userId = config.custom.username;

  unitFile = "monero-wallet-rpc.service";
in
{
  sops = {
    secrets = {
      "monero-wallet-rpc/username" = {
        inherit (config.custom) sopsFile;
        restartUnits = [ "${unitFile}" ];
      };
      "monero-wallet-rpc/password" = {
        inherit (config.custom) sopsFile;
        restartUnits = [ "${unitFile}" ];
      };
      "monero-wallet-rpc/wallet/password" = {
        inherit (config.custom) sopsFile;
        owner = userId;
        restartUnits = [ "${unitFile}" ];
      };
    };

    templates.moneroWalletRpcConfig = {
      owner = userId;
      # mode = "0400";
      restartUnits = [ "${unitFile}" ];
      content = ''
        # Which port to bind the RPC server on
        rpc-bind-port = ${toString walletRpcBindPort}

        # Point to your remote/full node
        daemon-address = ${monerodAddr}

        # RPC authentication username:password
        rpc-login = ${config.sops.placeholder."monero-wallet-rpc/username"}:${
          config.sops.placeholder."monero-wallet-rpc/password"
        }

        # If your node is untrusted (e.g. remote), set this
        # untrusted-daemon = 1

        # Disable any RPC calls that require a trusted daemon
        # restricted-rpc = 1

        # Where the wallet file lives
        wallet-file = ${walletFile}

        # File that contains your wallet password
        password-file = ${config.sops.secrets."monero-wallet-rpc/wallet/password".path}
      '';
    };
  };

  # We need to have the NFS share mounted *before* starting the service
  systemd = {
    services = {
      monero-wallet-rpc = {
        description = "Monero Wallet RPC";
        wantedBy = [ "multi-user.target" ];
        # Depend on the automount unit so systemd keeps retrying the NFS share
        requires = [ "mnt-data-srv.automount" ];
        after = [
          "mnt-data-srv.automount"
          "network.target"
          "monerod.service"
        ];
        path = [ pkgs.coreutils ];
        preStart = ''
          install -d -m 0750 -o ${userId} -g ${userId} ${walletHostDir}
        '';
        serviceConfig = {
          ExecStart = "${pkgs.monero-cli}/bin/monero-wallet-rpc --config-file ${walletRpcConfigFile}";
          Restart = "always";
          RestartSec = "10s";
          User = userId;
          Group = userId;
          WorkingDirectory = walletHostDir;
        };
      };

      # Restart the wallet RPC service every night at 3:00
      monero-wallet-rpc-restart = {
        description = "Restart the Monero Wallet RPC service";
        script = ''
          ${pkgs.systemd}/bin/systemctl restart ${unitFile}
        '';
      };
    };

    timers.monero-wallet-rpc-restart = {
      description = "Timer to regularly restart the Monero Wallet RPC service";
      timerConfig = {
        OnCalendar = "daily";
        RandomizedDelaySec = "6h"; # -> Between 00:00 and 06:00?
      };
      wantedBy = [ "timers.target" ];
    };
  };

  services.monit.config = lib.mkAfter ''
    check host "monero-wallet-rpc" with address "127.0.0.1"
      group services
      restart program = "${pkgs.systemd}/bin/systemctl restart ${unitFile}"
      if failed
        port ${toString walletRpcBindPort}
        type tcp
        with timeout 15 seconds
      then restart
      if 5 restarts within 10 cycles then alert
  '';

}
