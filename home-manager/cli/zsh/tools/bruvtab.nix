{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
lib.mkIf config.programs.firefox.enable {
  home.packages = [
    inputs.bruvtab.packages.${pkgs.stdenv.hostPlatform.system}.default
  ];
}
