{ config, ... }:
{
  # The app's ADB shell listener runs only on the home Wi-Fi networks; their
  # names stay in SOPS.
  sops.secrets."wifi/home-ssids" = { };
  fullNix.adbShell.allowedSsidsFile = config.sops.secrets."wifi/home-ssids".path;
}
