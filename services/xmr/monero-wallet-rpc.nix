{
  config,
  lib,
  pkgs,
  ...
}:
let
  monerodAddr = "http://${config.services.monero.rpc.address}:${toString config.services.monero.rpc.port}";

  walletRpcBindPort = 18084;
  walletHostDir = "/mnt/data/srv/monero-wallet-rpc";
  walletFile = "${walletHostDir}/data/xmrig-wallet";
  walletRpcConfigFile = config.sops.templates.moneroWalletRpcConfig.path;

  svcUser = "monero-wallet-rpc";
  svcGroup = "monero-wallet-rpc";

  unitFile = "monero-wallet-rpc.service";

  ensureWalletOwnership = pkgs.writeShellScript "monero-wallet-rpc-ensure-ownership" ''
    if ! ${pkgs.coreutils}/bin/chown --recursive "${svcUser}:${svcGroup}" "${walletHostDir}"
    then
      echo "Warning: failed to chown ${walletHostDir}" >&2
    fi
  '';
in
{
  sops = {
    secrets = {
      "monero-wallet-rpc/username" = {
        inherit (config.custom) sopsFile;
        restartUnits = [ unitFile ];
      };
      "monero-wallet-rpc/password" = {
        inherit (config.custom) sopsFile;
        restartUnits = [ unitFile ];
      };
      "monero-wallet-rpc/wallet/password" = {
        inherit (config.custom) sopsFile;
        owner = svcUser;
        restartUnits = [ unitFile ];
      };
    };

    templates.moneroWalletRpcConfig = {
      owner = svcUser;
      # mode = "0400";
      restartUnits = [ unitFile ];
      content = ''
        # Listen on all interfaces, praise the firewall
        rpc-bind-ip = 0.0.0.0
        # Which port to bind the RPC server on
        rpc-bind-port = ${toString walletRpcBindPort}

        # Point to your remote/full node
        daemon-address = ${monerodAddr}
        daemon-login = ${config.sops.placeholder."monerod/rpc/username"}:${
          config.sops.placeholder."monerod/rpc/password"
        }

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

  users.users.${svcUser} = {
    isSystemUser = true;
    description = "Monero Wallet RPC service user";
    group = svcGroup;
    home = walletHostDir;
    createHome = false;
  };
  users.groups.${svcGroup} = { };

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
        # FIXME This won't work since we don't run the service as root
        # preStart = ''
        #   install -d -m 0750 -o ${svcUser} -g ${svcGroup} ${walletHostDir}
        #   install -d -m 0750 -o ${svcUser} -g ${svcGroup} ${walletFileDir}
        # '';
        serviceConfig = {
          ExecStartPre = ensureWalletOwnership;
          ExecStart = "${pkgs.monero-cli}/bin/monero-wallet-rpc --config-file ${walletRpcConfigFile} --confirm-external-bind";
          PermissionsStartOnly = true;
          Restart = "always";
          RestartSec = "10s";
          User = svcUser;
          Group = svcGroup;
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

  # FIXME This does not work, since only the monero-waller-rpc user has access
  # to the wallet files!
  services.restic.backups.main.paths = [ walletHostDir ];

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
