{ config, ... }:
{
  imports = [ ./home-assistant-vm.nix ];

  services = {
    harmonia = {
      exposeMainDomain = false;
      extraVirtualHosts =
        map
          (domain: {
            domain = "cache.${config.networking.hostName}.${domain}";
            basicAuth = false;
          })
          [
            config.domains.tailscale
            config.domains.vpn
          ];
    };

    watchyourlan.interfaces = [
      "hass-br0"
      "wlp0s20f3"
    ];
  };
}
