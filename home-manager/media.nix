{ pkgs, ... }: {
  imports = [
    ./obs-studio.nix
  ];

  home.packages = with pkgs; [
    # Media
    ffmpeg-full
    mpv
    v4l-utils
    vlc

    ustreamer
    (pkgs.writeShellScriptBin "obs-studio-ustreamer" ''
      ${pkgs.ustreamer}/bin/ustreamer -d /dev/video10 "$@"
    '')
  ];
}
