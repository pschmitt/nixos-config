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
  imports = [ ../../../services/monit/netbird.nix ];

  sops.secrets.netbird-setup-key = {
    key = "netbird/setup-keys/${netbirdClientName}/${config.services.netbird.setupKeyName}";
    owner = "netbird-${netbirdClientName}";
    group = "netbird-${netbirdClientName}";
    mode = "0440";
  };

  users.users."${config.mainUser.username}".extraGroups = [
    "netbird-${netbirdClientName}"
  ];

  services = {
    netbird = {
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
          # login = {
          #   enable = true;
          #   setupKeyFile = config.sops.secrets."netbird-setup-key".path;
          # };
          dns-resolver = {
            # NOTE Having the addr set to the default value (null) will lead to nb
            # using its own addr
            address = "127.0.0.20";
            # NOTE for resolvectl to work reliably we need to leave the port on 53
            # other ports does not seem to work well with systemd-resolved
            port = 53;
          };
          environment = {
            # do not set up netbird ssh
            NB_ALLOW_SERVER_SSH = "false";
            # don't mess with my ssh config!
            NB_DISABLE_SSH_CONFIG = "true";
          };
        };
      };
    };

    # Don't let tailscale drop all our packets!
    tailscale =
      let
        tsFlags = [
          "--netfilter-mode=off"
        ];
      in
      {
        extraSetFlags = tsFlags;
        extraUpFlags = tsFlags;
      };
  };

  # HACK Fix netbird port forwarding
  networking =
    let
      netbirdInterfaces = map (c: c.interface) (builtins.attrValues config.services.netbird.clients);
    in
    {
      nat.internalInterfaces = lib.mkAfter netbirdInterfaces;
      firewall.trustedInterfaces = lib.mkAfter netbirdInterfaces;
    };

  # TODO Verify that the new services.netbird.tunnels.<name>.login.enable works (see above)
  # Then we should be able to safely delete the below autoconnect service.
  # https://github.com/NixOS/nixpkgs/blob/nixos-unstable/nixos/modules/services/networking/tailscale.nix#L172
  systemd.services."netbird-${netbirdClientName}-autoconnect" = {
    after = [ "netbird-${netbirdClientName}.service" ];
    wants = [ "netbird-${netbirdClientName}.service" ];
    # Hook into the netbird service rather than multi-user.target: this
    # oneshot waits for the management connection, which never happens
    # offline and would otherwise stall multi-user.target indefinitely.
    wantedBy = [ "netbird-${netbirdClientName}.service" ];

    serviceConfig = {
      Type = "oneshot";
    };

    environment = {
      NB_BIN = lib.getExe config.services.netbird.clients.${netbirdClientName}.wrapper;
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
    '';
  };

  environment.interactiveShellInit = ''
    alias netbird=netbird-${netbirdClientName}
  '';

  # We need to enable route_localnet to allow DNAT to 127.0.0.1.
  # This is used by modules/container-services.nix to redirect traffic
  # from the VPN interface to the container services listening on localhost.
  # We use a udev rule here because the interface is created dynamically
  # and might not exist when systemd-sysctl runs.
  # boot.kernel.sysctl = {
  #   "net.ipv4.conf.nb-${netbirdClientName}.route_localnet" = 1;
  # };
  services.udev.extraRules = ''
    SUBSYSTEM=="net", ACTION=="add", KERNEL=="nb-${netbirdClientName}", RUN+="${pkgs.procps}/bin/sysctl -w net.ipv4.conf.%k.route_localnet=1"
  '';
}
