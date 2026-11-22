{ pkgs, ... }:
{
  # The adb:: zsh functions only need adb itself; adb::scan uses nmap, ip
  # and jq.
  home.packages = [
    pkgs.android-tools
    pkgs.tpp-adb-shell
  ];
}
