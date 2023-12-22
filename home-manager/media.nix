{ pkgs, ... }: {
  imports = [
    ./obs-studio.nix
  ];

  home.packages = with pkgs; [
    # Media
    ffmpeg-full
    mpv
    ustreamer
    v4l-utils
    vlc
  ];
}
