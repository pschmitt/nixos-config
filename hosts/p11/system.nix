{ config, ... }:
{
  # p11's runtime was bootstrapped with a launcher whose stub sits here.
  system.launcherStub = "0x10000056e0";

  # sshd runs only on the home Wi-Fi networks; their names stay in SOPS.
  sops.secrets."wifi/home-ssids" = { };
  services.sshd.allowedSsidsFile = config.sops.secrets."wifi/home-ssids".path;
}
