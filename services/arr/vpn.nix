{
  config,
  inputs,
  lib,
  ...
}:
{
  imports = [
    inputs.vpn-confinement.nixosModules.default
    ../../profiles/network/snek/am-i-mullvad.nix
  ];

  sops.secrets."mullvad/config" = config.custom.mkSecret {
  };

  vpnNamespaces.mullvad = {
    enable = true;
    wireguardConfigFile = config.sops.secrets."mullvad/config".path;
    namespaceAddress = "10.67.42.2";
    bridgeAddress = "10.67.42.1";
    accessibleFrom = [
      # FIXME localhost bindings do *not* work, you'll have to use the
      # namespace address locally (or the nb/ts ips)
      # "127.0.0.1/32"

      # netbird + tailscale
      "100.64.0.0/10"
    ];
  };

  networking.extraHosts = ''
    ${config.vpnNamespaces.mullvad.namespaceAddress} mullvad.internal
    ${config.vpnNamespaces.mullvad.namespaceAddress} vpn.internal
  '';
  services.monit.config = lib.mkAfter ''
    check file "mullvad-netns" with path "/run/netns/mullvad"
      group piracy
      if does not exist then alert
  '';
}
