{
  config,
  lib,
  pkgs,
  ...
}:
let
  termuxMode = config.termux.enable or false;
in
{
  # The adb:: zsh functions only need adb itself; adb::scan uses nmap, ip
  # and jq.
  home.packages = lib.mkIf (!termuxMode) [ pkgs.android-tools ];

  termux.packages = lib.mkIf termuxMode [
    "android-tools"
    "iproute2"
    "nmap"
  ];
}
