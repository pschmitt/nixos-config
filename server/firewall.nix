{ config, lib, ... }:
let
  inherit (lib) attrNames mapAttrsToList mkBefore unique;

  tailscaleEnabled = (config.services ? tailscale) && config.services.tailscale.enable;
  netbirdEnabled = (config.services ? netbird) && config.services.netbird.enable;

  tailscaleInterfaces = if tailscaleEnabled then [ "tailscale0" ] else [ ];
  netbirdClients = if netbirdEnabled then config.services.netbird.clients else { };
  netbirdFallbackInterfaces = [ "netbird0" "netbird" ];
  netbirdInterfaces =
    if netbirdEnabled then
      unique (netbirdFallbackInterfaces ++ map (client: "nb-${client}") (attrNames netbirdClients))
    else
      [ ];

  tailscalePorts = if tailscaleEnabled then [ 41641 ] else [ ];
  netbirdPorts =
    if netbirdEnabled then
      builtins.filter (port: port != null) (
        mapAttrsToList (_: clientCfg: clientCfg.port or null) netbirdClients
      )
    else
      [ ];

  tcpPorts = [ 22 443 ];
  udpPorts = unique (tailscalePorts ++ netbirdPorts);
  trustedInterfaces = unique (tailscaleInterfaces ++ netbirdInterfaces);
in
{
  networking.firewall = {
    enable = lib.mkDefault true;
    allowedTCPPorts = lib.mkBefore tcpPorts;
    allowedUDPPorts = lib.mkBefore udpPorts;
    trustedInterfaces = lib.mkDefault trustedInterfaces;
    checkReversePath = lib.mkDefault "loose";
  };
}
