{ inputs, pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    curl
    dnsutils
    gitMinimal
    htop
    jq
    tmux
    inputs.tmux-slay.packages.${pkgs.stdenv.hostPlatform.system}.default
  ];
}
