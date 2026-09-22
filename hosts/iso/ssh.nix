{
  config,
  lib,
  ...
}:
let
  installerAuthorizedKeys = config.mainUser.authorizedKeys ++ [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGvVATHmFG1p5JqPkM2lE7wxCO2JGX3N5h9DEN3T2fKM nixos-anywhere"
  ];
in
{
  services.openssh.enable = true;
  systemd.services.sshd.wantedBy = lib.mkForce [ "multi-user.target" ];

  users.users = {
    nixos.openssh.authorizedKeys.keys = installerAuthorizedKeys;
    root.openssh.authorizedKeys.keys = installerAuthorizedKeys;
    "${config.mainUser.username}" = {
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
}
