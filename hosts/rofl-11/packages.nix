{ pkgs, ... }:
{
  environment.systemPackages = [ pkgs.yt-dlp ];
}
