{ pkgs, ... }:
{

  services = {
    dbus = {
      enable = true;
      packages = [ pkgs.gcr_4 ];
    };

    # enable keyring service
    gnome.gnome-keyring.enable = true;
    gnome.gcr-ssh-agent.enable = true;
  };

  # programs.seahorse.enable = true;
  environment.systemPackages = [ pkgs.seahorse ];

  xdg.portal.extraPortals = [ pkgs.gnome-keyring ];
}
