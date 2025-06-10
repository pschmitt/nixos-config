{ config, pkgs, ... }:
{
  sops.secrets."tailscale/auth-key" = { };

  services.tailscale = {
    enable = true;
    package = pkgs.master.tailscale;
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

  # environment.shellInit = ''
  #   # tailscale
  #   export TAILSCALE_IP=$(${pkgs.iproute2}/bin/ip -j -4 addr show dev tailscale0 | \
  #     ${pkgs.jq}/bin/jq -er '.[0].addr_info[0].local' 2>/dev/null)
  # '';
}
