{ inputs, pkgs, ... }:
{
  home.packages = with pkgs; [
    home-assistant-cli
    mosquitto
    shellyctl

    inputs.shelly-ble-rpc.packages.${pkgs.stdenv.hostPlatform.system}.default
  ];
}
