{
  config,
  inputs,
  pkgs,
  ...
}:
let
  ffmpegPkg = inputs.nixos-raspberrypi.packages.${pkgs.stdenv.hostPlatform.system}.ffmpeg_7-headless;
  libcameraPkg = inputs.nixos-raspberrypi.packages.${pkgs.stdenv.hostPlatform.system}.libcamera;
  raspberrypiUtilsPkg =
    inputs.nixos-raspberrypi.packages.${pkgs.stdenv.hostPlatform.system}.raspberrypi-utils;
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

  users.users."${config.mainUser.username}".extraGroups = [ "video" ];
}
