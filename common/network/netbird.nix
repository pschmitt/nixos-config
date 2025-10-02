{
  config,
  pkgs,
  lib,
  ...
}:
let
  netbirdPkg = pkgs.master.netbird;
  netbirdClients = config.services.netbird.clients or { };
  netbirdInterfaces =
    lib.unique (
      [ "netbird0" "netbird" ]
      ++ map (client: "nb-${client}") (builtins.attrNames netbirdClients)
    );
  netbirdPorts =
    builtins.filter (port: port != null) (
      lib.mapAttrsToList (_: clientCfg: clientCfg.port or null) netbirdClients
    );
in
{
  imports = [ ../monit/netbird.nix ];

  sops = {
    secrets.netbird-setup-key = {
      key = "netbird/setup-keys/netbird-io/${config.custom.netbirdSetupKey}";
      owner = "netbird-netbird-io";
      group = "netbird-netbird-io";
      mode = "0440";
    };
  };

  users.users."${config.custom.username}".extraGroups = [ "netbird-netbird-io" ];

  # mask netbird-wt0 service
  systemd.services.netbird-wt0.enable = false;

  services.netbird = {
    enable = true;
    package = netbirdPkg;

    ui = {
      enable = false;
      package = netbirdPkg;
    };

    clients = {
      netbird-io = {
        port = 51820;
        dns-resolver = {
          address = "127.0.0.20";
          port = 53;
        };
      };
    };
  };

  networking.firewall = lib.mkIf (config.services.netbird.enable or false) {
    trustedInterfaces = lib.mkAfter netbirdInterfaces;
    allowedUDPPorts = lib.mkBefore netbirdPorts;
  };

  # https://github.com/NixOS/nixpkgs/blob/nixos-unstable/nixos/modules/services/networking/tailscale.nix#L172
  systemd.services.netbird-netbird-io-autoconnect = {
    after = [ "netbird-netbird-io.service" ];
    wants = [ "netbird-netbird-io.service" ];
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      Type = "oneshot";
    };

    script = ''
      NB_BIN=/run/current-system/sw/bin/netbird-netbird-io

      # HOTFIX Do an explicit netbird up. This is mostly for new hosts - as
      # they don't seem to come up on their own after provisioning.
      $NB_BIN up

      # wait for connection to be established
      # TODO Wait till we get an IP?
      while ! "$NB_BIN" status --json | \
            ${lib.getExe pkgs.jq} -e '.management.connected' >/dev/null
      do
        sleep 0.5
      done

      # Store Netbird IP address in /etc/netbird/netbird.env
      if NETBIRD_IP=$($NB_BIN status --ipv4) && [[ -n $NETBIRD_IP ]]
      then
        mkdir -p /etc/containers/env
        echo "NETBIRD_IP=$NETBIRD_IP" > /etc/containers/env/netbird.env
      fi
    '';
  };

  environment.shellInit = ''
    # netbird ip
    source /etc/containers/env/netbird.env 2>/dev/null
    [[ -n $NETBIRD_IP ]] && export NETBIRD_IP
  '';

  environment.interactiveShellInit = ''
    alias netbird=netbird-netbird-io
  '';
}
