{ ... }:
{
  imports = [
    ./disk-config.nix
    ../../hardware/openstack-wiit.nix
  ];

  hardware = {
    cattle = true;
    kvmGuest = true;
    serverType = "openstack";
    biosBoot = false;
  };

  boot.loader.systemd-boot = {
    enable = true;
    configurationLimit = 3;
  };
  boot.loader.efi.canTouchEfiVariables = true;

  networking = {
    hostName = "deleteme";
    useDHCP = true;
    firewall.allowedTCPPorts = [ 22 ];
  };

  services.openssh = {
    enable = true;
    settings.PermitRootLogin = "prohibit-password";
  };

  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGvVATHmFG1p5JqPkM2lE7wxCO2JGX3N5h9DEN3T2fKM nixos-anywhere"
  ];

  system.stateVersion = "25.11";
}
