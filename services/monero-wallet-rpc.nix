{ config, ... }:
let
  monerodAddr = "http://host.docker.internal:${toString config.services.monero.rpc.port}";

  walletRpcBindPort = 18084;
  walletHostDir = "/mnt/data/srv/monerod/data/monero-wallet-rpc";
  walletContainerDir = "/home/monero";
  walletRpcConfigFile = "/etc/monero-wallet-rpc.conf";

  userId = "pschmitt";

  unitFile = "docker-monero-wallet-rpc.service";
in
{
  sops = {
    secrets = {
      "monero-wallet-rpc/username" = {
        sopsFile = config.custom.sopsFile;
        restartUnits = [ "${unitFile}" ];
      };
      "monero-wallet-rpc/password" = {
        sopsFile = config.custom.sopsFile;
        restartUnits = [ "${unitFile}" ];
      };
      "monero-wallet-rpc/wallet/password" = {
        sopsFile = config.custom.sopsFile;
        restartUnits = [ "${unitFile}" ];
        owner = userId;
      };
    };

    templates.moneroWalletRpcConfig = {
      owner = userId;
      # mode = "0400";
      content = ''
        # Which port to bind the RPC server on
        rpc-bind-port = ${toString walletRpcBindPort}

        # Point to your remote/full node
        daemon-address = ${monerodAddr}

        # If your node is untrusted (e.g. remote), set this
        untrusted-daemon = 1

        # RPC authentication username:password
        rpc-login = ${config.sops.placeholder."monero-wallet-rpc/username"}:${
          config.sops.placeholder."monero-wallet-rpc/password"
        }

        # Disable any RPC calls that require a trusted daemon
        restricted-rpc = 1

        # Where the wallet file lives INSIDE the container
        wallet-file = ${walletContainerDir}/wallet/xmrig-wallet

        # File that contains your wallet password (also inside container)
        # password-file = ${walletContainerDir}/wallet/xmrig-wallet-password
        password-file = /wallet-password
      '';
    };
  };

  virtualisation.oci-containers.containers = {
    # Forward host.docker.internal:108084 -> localhost:18084
    monerod-relay = {
      image = "alpine/socat:latest";
      pull = "always";

      extraOptions = [
        "--network=host"
        "--add-host=host.docker.internal:host-gateway"
      ];

      cmd = [
        "TCP-LISTEN:${toString config.services.monero.rpc.port},fork,bind=host.docker.internal"
        "TCP-CONNECT:127.0.0.1:${toString config.services.monero.rpc.port}"
      ];
    };

    monero-wallet-rpc = {
      image = "sethsimmons/simple-monero-wallet-rpc:latest";
      pull = "always";
      autoStart = true;

      extraOptions = [
        # "--user=${userId}:${groupId}"
        "--add-host=host.docker.internal:host-gateway"
      ];

      volumes = [
        "${walletHostDir}:${walletContainerDir}"
        "${config.sops.templates.moneroWalletRpcConfig.path}:${walletRpcConfigFile}:ro"
        "${config.sops.secrets."monero-wallet-rpc/wallet/password".path}:/wallet-password:ro"
      ];

      ports = [
        # localhost
        # "127.0.0.1:${toString walletRpcBindPort}:${toString walletRpcBindPort}"
        "${toString walletRpcBindPort}:${toString walletRpcBindPort}"
      ];

      cmd = [ "--config-file=${walletRpcConfigFile}" ];
      # cmd = [
      #   "--rpc-bind-port=${toString walletRpcBindPort}"
      #   "--daemon-address=${monerodAddr}"
      #   "--untrusted-daemon"
      #   "--rpc-login=${monerodRpcUsername}:${monerodRpcPassword}"
      #   "--restricted-rpc"
      #   "--wallet-file=${walletContainerDir}/wallet/xmrig-wallet"
      #   "--password-file=${walletContainerDir}/wallet/xmrig-wallet-password"
      # ];
    };
  };
}
