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

    # The `luks-ssh-unlock tui` dashboard runs as the user; targets whose
    # keys, known_hosts and passphrases only root can read are checked and
    # unlocked through the privileged helper. Admin also allows a forced
    # unlock and starting/stopping a target's unit, as sudo did before.
    luks-ssh-unlock.helper = {
      enable = true;
      adminUsers = [ config.mainUser.username ];
    };

    watchyourlan.interfaces = [
      "hass-br0"
      "wlp0s20f3"
    ];
  };
}
