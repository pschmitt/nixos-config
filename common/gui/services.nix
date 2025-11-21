{
  services = {
    avahi = {
      enable = true;
      nssmdns4 = true;
    };

    dbus = {
      enable = true;
      implementation = "broker";
    };

    # enable sushi and rygel
    gnome = {
      gnome-online-accounts.enable = true;
      sushi.enable = true;
      rygel.enable = true;
    };

    gvfs.enable = true;
    seatd.enable = true;
    tumbler.enable = true;
  };
}
