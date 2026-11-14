{ config, ... }:
{
  imports = [ ./home-assistant-vm.nix ];

  sops.secrets."luks-ssh-unlock/fnuc-identity" = config.sops.mkHostSecret {
    key = "users/${config.mainUser.username}/ssh/ed25519/privkey";
    mode = "0400";
  };

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
    # The helper only trusts root-owned key files: authenticate with a
    # root-only copy of the personal key instead of the one in $HOME.
    luks-ssh-unlock-fleet.selfKeyPath = config.sops.secrets."luks-ssh-unlock/fnuc-identity".path;

    watchyourlan.interfaces = [
      "hass-br0"
      "wlp0s20f3"
    ];
  };
}
