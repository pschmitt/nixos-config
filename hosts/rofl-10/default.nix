{ lib, ... }:
{
  imports = [
    ./disk-config.nix
    ./hardware-configuration.nix

    ../../server
    ../../server/optimist.nix
  ];

  custom.cattle = true;
  custom.promptColor = "#0B87CA"; # nextcloud blue

  # Enable networking
  networking = {
    hostName = lib.strings.trim (builtins.readFile ./HOSTNAME);
    # Disable the firewall altogether.
    firewall = {
      enable = false;
      # allowedTCPPorts = [ ... ];
      # allowedUDPPorts = [ ... ];
    };
  };

  # environment.systemPackages = with pkgs; [ ];

  # TODO remove once the migration is done
  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIO0JnT7KCUHAGF8l0H2+zdn+0gx8Jv+b828yzaG1KZ3y root@rofl-09"
  ];
}
