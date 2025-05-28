{ ... }:
{
  users.users."ssh-tunnel-turris" = {
    isSystemUser = true;
    group = "ssh-tunnel-turris";
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIF945oD6xv+KL/P7m4JxdnOxljsm1UcKVNfE+KASu2ZX root@turris"
    ];
  };
  users.groups.ssh-tunnel-turris = { };
}
