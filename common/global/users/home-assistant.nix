{ pkgs, ... }:
{
  users.users.home-assistant = {
    isSystemUser = true;
    description = "Home Assistant remote access";
    group = "home-assistant";
    shell = pkgs.bash;
    home = "/var/lib/home-assistant";
    createHome = true;
    openssh.authorizedKeys.keys = [
      # Home Assistant container on hv
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKtJvOe/V+obZ1lS2L/qUAUVDUSFapVKin07BUZSHAU7 root@a0d7b954-ssh"
    ];
  };

  users.groups.home-assistant = { };
}
