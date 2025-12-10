{ config, lib, ... }:
{
  services.displayManager.gdm = {
    enable = true;
    debug = true;
    settings = { };
    autoLogin.delay = 0;
  };

  services.displayManager = {
    autoLogin = {
      enable = true;
      user = config.mainUser.username;
    };

    defaultSession = lib.mkDefault "hyprland-uwsm";
  };

  # https://github.com/NixOS/nixpkgs/pull/282317
  security.pam.services.gdm.enableGnomeKeyring = true;
  security.pam.services.login.enableGnomeKeyring = true;

  # GDM monitor configuration
  # systemd.tmpfiles.rules = [
  #   "L+ /run/gdm/.config/monitors.xml - - - - ${pkgs.writeText "gdm-monitors.xml" ''
  #     <!-- this should all be copied from your ~/.config/monitors.xml -->
  #     <monitors version="2">
  #       <configuration>
  #           <!-- REDACTED -->
  #       </configuration>
  #     </monitors>
  #   ''}"
  # ];

  # https://nixos.wiki/wiki/GNOME#automatic_login
  # Below fixes Gnome starting instead of hyprland
  # https://github.com/NixOS/nixpkgs/issues/334404
  systemd.services."autovt@tty1".enable = false;
  systemd.services."getty@tty1".enable = false;
}
