{
  config,
  lib,
  pkgs,
  ...
}:
let
  tailscalePkg = pkgs.master.tailscale;

  tailscaleFlags = [
    "--advertise-exit-node"
    "--accept-dns"
    "--operator=${config.mainUser.username}"
  ];
in
{
  imports = [ ../../services/monit/tailscale.nix ];

  sops.secrets."tailscale/auth-key" = {
    restartUnits = [
      "tailscaled-autoconnect.service"
    ];
  };

  services.tailscale = {
    enable = true;
    package = tailscalePkg;
    openFirewall = true;
    extraSetFlags = tailscaleFlags;
    extraUpFlags = tailscaleFlags ++ [ "--reset" ]; # enforce!
    useRoutingFeatures = "both";
    authKeyFile = config.sops.secrets."tailscale/auth-key".path;
  };

  networking.firewall.trustedInterfaces = lib.mkAfter [
    config.services.tailscale.interfaceName
  ];

  systemd.services.tailscaled-autoconnect.postStart = ''
    # Store Tailscale IP address in /etc/containers/env/tailscale.env
    if TAILSCALE_IP=$(${tailscalePkg}/bin/tailscale ip -4) && \
       [[ -n $TAILSCALE_IP ]]
    then
      mkdir -p /etc/containers/env
      echo "TAILSCALE_IP=$TAILSCALE_IP" > /etc/containers/env/tailscale.env
    fi
  '';

  environment.shellInit = ''
    # tailscale ip
    source /etc/containers/env/tailscale.env 2>/dev/null
    [[ -n $TAILSCALE_IP ]] && export TAILSCALE_IP
  '';

  # We need to enable route_localnet to allow DNAT to 127.0.0.1.
  # This is used by modules/container-services.nix to redirect traffic
  # from the VPN interface to the container services listening on localhost.
  # We use a udev rule here because the interface is created dynamically
  # and might not exist when systemd-sysctl runs.
  # boot.kernel.sysctl = {
  #   "net.ipv4.conf.${config.services.tailscale.interfaceName}.route_localnet" = 1;
  # };
  services.udev.extraRules = ''
    SUBSYSTEM=="net", ACTION=="add", KERNEL=="${config.services.tailscale.interfaceName}", RUN+="${pkgs.procps}/bin/sysctl -w net.ipv4.conf.%k.route_localnet=1"
  '';
}
