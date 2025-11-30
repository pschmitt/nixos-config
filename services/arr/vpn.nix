{ config, inputs, ... }:
{
  imports = [
    inputs.vpn-confinement.nixosModules.default
    ../../common/network/snek/am-i-mullvad.nix
  ];

  sops.secrets."mullvad/config" = {
    inherit (config.custom) sopsFile;
  };

  vpnNamespaces.mullvad = {
    enable = true;
    wireguardConfigFile = config.sops.secrets."mullvad/config".path;
    namespaceAddress = "10.67.42.2";
    bridgeAddress = "10.67.42.1";
    accessibleFrom = [
      "100.64.0.0/10"
    ];
  };

  networking.extraHosts = ''
    ${config.vpnNamespaces.mullvad.namespaceAddress} mullvad.local
  '';

}
