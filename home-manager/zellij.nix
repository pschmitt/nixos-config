{ inputs, pkgs, ... }:
{
  home.packages = [
    pkgs.zellij
    inputs.zjstatus.packages.${pkgs.stdenv.hostPlatform.system}.default
  ];

  home.file.".config/zellij/plugins/zjstatus.wasm" = {
    source = "${inputs.zjstatus.packages.${pkgs.stdenv.hostPlatform.system}.default}/bin/zjstatus.wasm";
  };
}
