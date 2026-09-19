{ pkgs, ... }:
{
  # Nicer console on the physical/KVM display, matching ge2/gk4.
  services.kmscon = {
    enable = true;
    config = {
      hwaccel = true;
      "font-name" = "Comic Code";
      "dpms-timeout" = 0;
    };
  };

  # lrz doesn't import profiles/gui, so the font package isn't pulled in
  # implicitly like it is for the laptop hosts this kmscon config is copied from.
  fonts.packages = [ pkgs.ComicCode ];

  # Required for kmscon hwaccel above.
  hardware.graphics.enable = true;
}
