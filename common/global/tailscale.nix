{ config, lib, ... }: {
  age.secrets.ts-auth-key.file = ../../secrets/tailscale-auth-key.age;

  services.tailscale = {
    enable = true;
    openFirewall = true;
    extraUpFlags = lib.optionalString config.services.netbird.enable [ "--netfilter-mode=off" ];
    useRoutingFeatures = "both";
    authKeyFile = config.age.secrets.ts-auth-key.path;
  };
}
