{ config, ... }: {
  age.secrets.ts-auth-key.file = ../../secrets/tailscale-auth-key.age;

  services.tailscale = {
    enable = true;
    openFirewall = true;
    extraUpFlags = if config.services.netbird.enable then [ "--netfilter-mode=off" ] else [];
    useRoutingFeatures = "both";
    authKeyFile = config.age.secrets.ts-auth-key.path;
  };
}
