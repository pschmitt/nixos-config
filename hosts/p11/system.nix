{ config, ... }:
{
  # sshd runs only on the home Wi-Fi networks; their names stay in SOPS.
  sops.secrets."wifi/home-ssids" = { };
  services.sshd.allowedSsidsFile = config.sops.secrets."wifi/home-ssids".path;
}
