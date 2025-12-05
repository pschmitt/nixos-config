{
  config,
  lib,
  pkgs,
  ...
}:
{
  boot = {
    # FIX v4l2loopback is not building with 6.18 yet.
    # Fix is not yet in nixos-unstable as of 2025-12-05:
    # https://github.com/NixOS/nixpkgs/pull/467572
    kernelPackages = lib.mkForce pkgs.linuxPackages_6_17;

    extraModulePackages = [ config.boot.kernelPackages.v4l2loopback ];
    kernelModules = [ "v4l2loopback" ];
    extraModprobeConfig = ''
      # exclusive_caps: Skype, Zoom, Teams etc. will only show device when actually streaming
      # card_label: Name of virtual camera, how it'll show up in Skype, Zoom, Teams
      # https://github.com/umlaeute/v4l2loopback
      options v4l2loopback video_nr=10 exclusive_caps=1 card_label="OBS Virtual Camera"
    '';
  };
}
