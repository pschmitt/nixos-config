{ config, pkgs, ... }:
let
  tailscalePkg = pkgs.master.tailscale;
in
{
  sops.secrets."tailscale/auth-key" = { };

  services.tailscale = {
    enable = true;
    package = tailscalePkg;
    openFirewall = true;
    extraUpFlags =
      if config.services.netbird.enable then
        [
          "--netfilter-mode=off"
          "--accept-dns=false"
        ]
      else
        [ "--accept-dns=false" ];
    useRoutingFeatures = "both";
    authKeyFile = config.sops.secrets."tailscale/auth-key".path;
  };

  environment.systemPackages = [ pkgs.master.tailscale ];

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
