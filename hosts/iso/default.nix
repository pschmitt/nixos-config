{
  config,
  lib,
  pkgs,
  ...
}:
let
  installerAuthorizedKeys = config.custom.authorizedKeys ++ [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGvVATHmFG1p5JqPkM2lE7wxCO2JGX3N5h9DEN3T2fKM nixos-anywhere"
  ];
in
{
  services.openssh.enable = true;
  # Ensure sshd is started out of the box.
  systemd.services.sshd.wantedBy = lib.mkForce [ "multi-user.target" ];

  users.users = {
    nixos.openssh.authorizedKeys.keys = installerAuthorizedKeys;
    root.openssh.authorizedKeys.keys = installerAuthorizedKeys;

    "${config.custom.username}" = {
      isNormalUser = true;
      group = "users";
      extraGroups = [
        "networkmanager"
        "video"
        "wheel"
      ];
      openssh.authorizedKeys.keys = installerAuthorizedKeys;
    };
  };

  isoImage.squashfsCompression = "gzip -Xcompression-level 1";
  networking = {
    useDHCP = lib.mkForce true;
    nameservers = [
      "1.1.1.1"
      "8.8.8.8"
    ];
  };

  environment.systemPackages = with pkgs; [
    htop
    rsync # required for nixos-anywhere
  ];
}
