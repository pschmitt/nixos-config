{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  ffmpegPkg = inputs.nixos-raspberrypi.packages.${pkgs.system}.ffmpeg_7-headless;
  libcameraPkg = inputs.nixos-raspberrypi.packages.${pkgs.system}.libcamera;
  raspberrypiUtilsPkg = inputs.nixos-raspberrypi.packages.${pkgs.system}.raspberrypi-utils;

  camPath = "cam";
  ffmpegBin = "${ffmpegPkg}/bin/ffmpeg";
  v4l2Dev = "/dev/video0";
in
{
  # minimal firmware reminder:
  # /boot/firmware/config.txt needs:
  # start_x=1
  # gpu_mem=128

  environment.systemPackages = with pkgs; [
    ffmpegPkg
    libcameraPkg
    raspberrypiUtilsPkg
    v4l-utils
  ];

  users.users."${config.custom.username}".extraGroups = [ "video" ];
}
