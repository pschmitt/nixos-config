{ config, lib, ... }: {
  services.tailscale = {
    enable = true;
    openFirewall = true;
    extraUpFlags = lib.optionalString config.services.netbird.enable [ "--netfilter-mode=off" ];
  };
}
