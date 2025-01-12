{ config, ... }:
{
  services.xserver.displayManager.gdm = {
    enable = true;
    debug = true;
    settings = { };
    autoLogin.delay = 0;
  };

  services.displayManager = {
    autoLogin = {
      enable = true;
      user = config.custom.username;
    };

    defaultSession = "hyprland-uwsm";
  };

  # https://nixos.wiki/wiki/GNOME#automatic_login
  # Below fixes Gnome starting instead of hyprland
  # https://github.com/NixOS/nixpkgs/issues/334404
  systemd.services."autovt@tty1".enable = false;
  systemd.services."getty@tty1".enable = false;
}
