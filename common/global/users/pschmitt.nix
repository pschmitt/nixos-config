{ pkgs, config, ... }:
{
  sops.secrets."users/pschmitt/password".neededForUsers = true;

  users.users."${config.custom.username}" = {
    uid = 1000;
    isNormalUser = true;
    description = config.custom.fullName;
    group = config.custom.username;
    # Below requires mutableUsers = false (set in users.nix)
    hashedPasswordFile = config.sops.secrets."users/pschmitt/password".path;
    extraGroups = [
      "cdrom"
      "docker"
      "dialout" # for /dev/tty{ACM,USB}*
      "libvirtd"
      "mlocate"
      "users"
      "wheel"
      "wireshark"
    ];
    openssh.authorizedKeys.keys = config.custom.authorizedKeys ++ [
      # hass-fnuc
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKtJvOe/V+obZ1lS2L/qUAUVDUSFapVKin07BUZSHAU7"
    ];
    shell = pkgs.zsh;
  };

  # Below is required for some reason when using greetd with autologin
  users.groups."${config.custom.username}" = { };
}
