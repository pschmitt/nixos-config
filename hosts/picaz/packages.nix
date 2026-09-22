{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    curl
    htop
    v4l-utils
  ];
}
