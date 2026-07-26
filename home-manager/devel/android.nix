{
  config,
  inputs,
  pkgs,
  ...
}:
let
  system = pkgs.stdenv.hostPlatform.system;
in
{
  imports = [ inputs.declaroid.homeManagerModules.default ];

  home.packages = with pkgs; [
    aapt # aapt2, e.g. `aapt2 dump badging some.apk`
    android-tools # adb + fastboot
    inputs.tsvtool.packages.${system}.default # pretty TSV/JSON/YAML/TOML tables, used by declaroid's devices/diff output
    pmbootstrap
    scrcpy
  ];

  # configPath must be the live checkout, not a Nix-store copy:
  # android/all.yaml's `configs:` entries (mp4.yaml/px5.yaml/zf10.yaml) are
  # relative paths resolved against the config file's own directory, which
  # only exists in the real repo. See the option's own description
  # (declaroid's home-manager-module.nix) for why this -- not
  # $DECLAROID_CONFIG -- is what actually keeps `apply --enforce` from
  # ever silently targeting the wrong config: confirmed as a real
  # incident, a stale-environment shell fell back to declaroid's own
  # small built-in default and offered to uninstall every real app on two
  # devices.
  programs.declaroid = {
    enable = true;
    configPath = "${config.home.homeDirectory}/devel/private/pschmitt/nixos-config.git/android/all.yaml";
  };
}
