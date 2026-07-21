{ inputs, pkgs, ... }:
let
  system = pkgs.stdenv.hostPlatform.system;
in
{
  home.packages = with pkgs; [
    android-tools # adb + fastboot
    inputs.declaroid.packages.${system}.default # declarative app provisioning, see https://github.com/pschmitt/declaroid
    inputs.tsvtool.packages.${system}.default # pretty TSV/JSON/YAML/TOML tables, used by declaroid's devices/diff output
    pmbootstrap
  ];

  xdg.configFile."declaroid/apps.yaml".source = ../../android/apps.yaml;
}
