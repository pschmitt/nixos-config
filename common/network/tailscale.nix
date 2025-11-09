{
  config,
  lib,
  pkgs,
  ...
}:
let
  tailscalePkg = pkgs.master.tailscale;

  tailscaleFlags = [
    "--reset" # enforce!
    "--advertise-exit-node"
    "--accept-dns"
    "--operator=${config.custom.username}"
  ];
in
{
  imports = [ ../monit/tailscale.nix ];

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
    extraUpFlags = tailscaleFlags;
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
}
