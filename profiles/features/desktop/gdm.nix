{
  config,
  lib,
  pkgs,
  ...
}:
let
  useOo7 = config.services.oo7.enable;
  keyringOrder = config.security.pam.services.gdm-autologin.rules.auth.gnome_keyring.order;
in
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
    gdm.enableGnomeKeyring = !useOo7;
    login.enableGnomeKeyring = !useOo7;

    # services.oo7 adds pam_oo7 to `login` (gdm-password and the
    # gdm-autologin session stack include it), but gdm-autologin has its own
    # auth stack with a hardcoded gnome_keyring rule, so pam_oo7 has to be
    # added there by hand to pick up the authtok.
    gdm-autologin.rules.auth.oo7 = lib.mkIf useOo7 {
      control = "optional";
      modulePath = "${pkgs.oo7-pam}/lib/security/pam_oo7.so";
      order = keyringOrder + 10;
    };

    # Bridge the LUKS passphrase into the GDM-autologin keyring unlock.
    #
    # systemd-cryptsetup caches the passphrase entered at boot in the kernel
    # keyring (keyname "cryptsetup"); pam_systemd_loadkey reads it back out and
    # sets it as the PAM authtok, so pam_gnome_keyring / pam_oo7 (enabled for
    # autologin above) unlocks the login keyring with it — no second password
    # prompt, no rbw/sops in the login path. This requires a systemd initrd and
    # a login keyring password matching the LUKS passphrase (true on all
    # workstations: ge2, gk4, x13).
    #
    # This only unlocks at login. gnome-keyring-daemon crashes periodically and
    # respawns with a locked keyring; the gnome-keyring-auto-unlock
    # service+timer (home-manager/gui/gnome-keyring.nix) handle that mid-session
    # recovery. With oo7, the daemon unlocks itself from a credential instead.
    #
    # Slotted right after pam_gdm, right before the keyring module.
    gdm-autologin.rules.auth.systemd_loadkey = {
      control = "optional";
      modulePath = "${config.systemd.package}/lib/security/pam_systemd_loadkey.so";
      order = keyringOrder - 50;
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
