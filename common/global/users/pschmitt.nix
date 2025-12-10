{ pkgs, config, ... }:
{
  sops.secrets."users/pschmitt/password".neededForUsers = true;

  users.users."${config.mainUser.username}" = {
    uid = 1000;
    isNormalUser = true;
    description = config.mainUser.fullName;
    group = config.mainUser.username;
    # Below requires mutableUsers = false (set in users.nix)
    hashedPasswordFile = config.sops.secrets."users/pschmitt/password".path;
    extraGroups = [
      "cdrom"
      "dialout" # for /dev/tty{ACM,USB}*
      "docker"
      "libvirtd"
      "mlocate"
      "users"
      "wheel"
      "wireshark"
    ];
    openssh.authorizedKeys.keys = config.mainUser.authorizedKeys ++ [
      # hass-fnuc
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKtJvOe/V+obZ1lS2L/qUAUVDUSFapVKin07BUZSHAU7"
    ];
    shell = pkgs.zsh;
  };

  # Below is required for some reason when using greetd with autologin
  users.groups."${config.mainUser.username}" = { };

  # Set GDM user profile picture
  # https://discourse.nixos.org/t/setting-the-user-profile-image-under-gnome/36233/7
  systemd.tmpfiles.rules =
    let
      profilepic = builtins.fetchurl {
        # NOTE setting the extension to .png is required for hyprlock to detect
        # the filetype correctly
        # https://github.com/hyprwm/hyprlock/issues/317
        name = "face.png";
        url = "https://www.gravatar.com/avatar/8635e7a28259cb6da1c6a3c96c75b425.png?size=96";
        sha256 = "1kg0x188q1g2mph13cs3sm4ybj3wsliq2yjz5qcw4qs8ka77l78p";
      };
    in
    [
      # notice the "\\n" we don't want nix to insert a new line in our string, just pass it as \n to systemd
      "f+ /var/lib/AccountsService/users/${config.mainUser.username}  0600 root root - [User]\\nIcon=/var/lib/AccountsService/icons/${config.mainUser.username}\\n"
      "L+ /var/lib/AccountsService/icons/${config.mainUser.username}  - - - - ${profilepic}"
    ];
}
