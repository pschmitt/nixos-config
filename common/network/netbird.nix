{
  config,
  pkgs,
  lib,
  ...
}:
let
  netbirdPkg = pkgs.master.netbird;
  netbirdClientName = "netbird-io";
in
{
  imports = [ ../monit/netbird.nix ];

  sops = {
    secrets.netbird-setup-key = {
      key = "netbird/setup-keys/${netbirdClientName}/${config.custom.netbirdSetupKey}";
      owner = "netbird-${netbirdClientName}";
      group = "netbird-${netbirdClientName}";
      mode = "0440";
    };
  };

  users.users."${config.custom.username}".extraGroups = [
    "netbird-${netbirdClientName}"
  ];

  services.netbird = {
    enable = true;
    package = netbirdPkg;

    ui = {
      enable = lib.mkDefault false;
      package = netbirdPkg;
    };

    # NOTE We use mkForce here to remove the "default" client
    clients = lib.mkForce {
      "${netbirdClientName}" = {
        port = 51820;
        dns-resolver = {
          # NOTE Having the addr set to the default value (null) will lead to nb
          # using its own addr
          address = "127.0.0.20";
          # NOTE for resolvectl to work reliably we need to leave the port on 53
          # other ports does not seem to work well with systemd-resolved
          port = 53;
        };
      };
    };
  };

  networking.firewall.trustedInterfaces = lib.mkAfter (
    map (c: c.interface) (builtins.attrValues config.services.netbird.clients)
  );

  # https://github.com/NixOS/nixpkgs/blob/nixos-unstable/nixos/modules/services/networking/tailscale.nix#L172
  systemd.services."netbird-${netbirdClientName}-autoconnect" = {
    after = [ "netbird-${netbirdClientName}.service" ];
    wants = [ "netbird-${netbirdClientName}.service" ];
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      Type = "oneshot";
    };

    environment = {
      NB_BIN = "/run/current-system/sw/bin/netbird-${netbirdClientName}";
      NB_HOSTNAME = config.networking.hostName;
      NB_SETUP_KEY_FILE = config.sops.secrets."netbird-setup-key".path;
    };

    script = ''
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
    alias netbird=netbird-${netbirdClientName}
  '';
}
