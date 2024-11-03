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
}
