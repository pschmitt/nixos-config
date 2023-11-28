{ config, pkgs, hyprlandPkg, hyprland-wrapper, ... }:
let
  # https://www.reddit.com/r/NixOS/comments/14rhsnu/regreet_greeter_for_greetd_doesnt_show_a_session/
  regreet-override = pkgs.greetd.regreet.overrideAttrs (final: prev: {
    SESSION_DIRS = "${config.services.xserver.displayManager.sessionData.desktops}/share";
  });

in
{
  # https://nixos.wiki/wiki/Greetd
  services.greetd = {
    enable = true;
    restart = false; # Restart greetd when it crashes
    settings = rec {
      initial_session = {
        # command = "${hyprlandPkg}/bin/Hyprland";
        command = "${hyprland-wrapper}/bin/hyprland-wrapper";
        user = config.custom.username;
      };
      # default_session = initial_session;
      default_session = {
        command =
          "${pkgs.dbus}/bin/dbus-run-session ${pkgs.cage}/bin/cage -s -- ${pkgs.greetd.regreet}/bin/regreet";
        user = "greeter";
      };
    };
  };

  programs.regreet = {
    enable = true;
    package = regreet-override;
    settings = {
      # background = {
      #   path = "xxx";
      #   fit = "Contain";
      # };
      GTK = {
        application_prefer_dark_theme = true;
        cursor_theme_name = "Adwaita";
        font_name = "Noto Sans 16";
        icon_theme_name = "Adwaita";
        theme_name = "Adwaita";
      };
      commands = {
        reboot = [ "systemctl" "reboot" ];
        poweroff = [ "systemctl" "poweroff" ];
      };
    };
  };

  # Below is required for some weird reason when using greetd with autologin
  users.groups.pschmitt = { };
}
