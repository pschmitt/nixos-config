{ inputs, pkgs, ... }: {
  home.packages = [
    pkgs.zellij
    inputs.zjstatus.packages.${pkgs.system}.default
  ];

  home.file.".config/zellij/plugins/zjstatus.wasm" = {
    source = "${inputs.zjstatus.packages.${pkgs.system}.default}/bin/zjstatus.wasm";
  };
}
