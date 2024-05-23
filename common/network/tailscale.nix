{ config, ... }: {
  sops.secrets."tailscale/auth-key" = { };

  services.tailscale = {
    enable = true;
    openFirewall = true;
    extraUpFlags = if config.services.netbird.enable then [ "--netfilter-mode=off" ] else [ ];
    useRoutingFeatures = "both";
    authKeyFile = config.sops.secrets."tailscale/auth-key".path;
  };
}
