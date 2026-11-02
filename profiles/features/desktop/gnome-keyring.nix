{
  config,
  lib,
  pkgs,
  ...
}:
let
  # oo7 (services.oo7, on by default here) replaces gnome-keyring-daemon as
  # the Secret Service provider. Both claim org.freedesktop.secrets, so exactly
  # one of them may run. On first unlock oo7 migrates the legacy
  # ~/.local/share/keyrings/*.keyring files and deletes the originals.
  useOo7 = config.services.oo7.enable;
in
{
  services = {
    oo7.enable = lib.mkDefault true;

    dbus = {
      enable = true;
      # gcr-prompter (org.gnome.keyring.SystemPrompter) also serves oo7's
      # password prompts outside GNOME Shell.
      packages = [ pkgs.gcr_4 ];
    };

    gnome.gnome-keyring.enable = !useOo7;
    # oo7 has no SSH agent; keep gcr's.
    gnome.gcr-ssh-agent.enable = true;
  };

  # programs.seahorse.enable = true;
  environment.systemPackages = [ pkgs.seahorse ];

  xdg.portal.extraPortals = lib.optional (!useOo7) pkgs.gnome-keyring;
}
