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

  # Below is required to unlock the keyring with the LUKS passphrase
  # https://discourse.nixos.org/t/automatically-unlocking-the-gnome-keyring-using-luks-key-with-greetd-and-hyprland/54260/3
  boot.initrd.systemd.enable = true;

  # https://nixos.wiki/wiki/GNOME#automatic_login
  # Below fixes Gnome starting instead of hyprland
  # https://github.com/NixOS/nixpkgs/issues/334404
  systemd.services."autovt@tty1".enable = false;
  systemd.services."getty@tty1".enable = false;
}
