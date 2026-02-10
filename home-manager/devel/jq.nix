{ inputs, pkgs, ... }:
{
  home.packages = with pkgs; [
    jc
    jq
    jsonrepair
    inputs.mq.packages.${pkgs.stdenv.hostPlatform.system}.mq
    yq-go
  ];
}
