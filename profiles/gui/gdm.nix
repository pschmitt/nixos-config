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
  security.pam.services = {
    gdm.enableGnomeKeyring = true;
    login.enableGnomeKeyring = true;

    # Bridge the LUKS passphrase into the GDM-autologin keyring unlock.
    #
    # systemd-cryptsetup caches the passphrase entered at boot in the kernel
    # keyring (keyname "cryptsetup"); pam_systemd_loadkey reads it back out and
    # sets it as the PAM authtok, so pam_gnome_keyring (enabled for autologin
    # above) unlocks the login keyring with it — no second password prompt, no
    # rbw/sops in the login path. Requires boot.initrd.systemd.enable
    # (profiles/gui/gnome-keyring.nix) and the login keyring password to equal
    # the LUKS passphrase (true on all workstations: ge2, gk4, x13).
    #
    # This only unlocks at login. gnome-keyring-daemon crashes periodically and
    # respawns with a locked keyring; the gnome-keyring-auto-unlock
    # service+timer (home-manager/gui/gnome-keyring.nix) handle that mid-session
    # recovery.
    #
    # Slotted right after pam_gdm (10300), right before gnome_keyring (10400).
    gdm-autologin.rules.auth.systemd_loadkey = {
      control = "optional";
      modulePath = "${config.systemd.package}/lib/security/pam_systemd_loadkey.so";
      order = config.security.pam.services.gdm-autologin.rules.auth.gnome_keyring.order - 50;
    };
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

  # https://nixos.wiki/wiki/GNOME#automatic_login
  # Below fixes Gnome starting instead of hyprland
  # https://github.com/NixOS/nixpkgs/issues/334404
  systemd.services."autovt@tty1".enable = false;
  systemd.services."getty@tty1".enable = false;
}
