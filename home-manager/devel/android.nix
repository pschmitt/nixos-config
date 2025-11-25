{ pkgs, ... }:
{
  home.packages = with pkgs; [

    # android
    android-tools # adb + fastboot
    pmbootstrap
  ];
}
