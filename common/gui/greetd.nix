{ lib, config, pkgs, hyprlandPkg, hyprland-wrapper, ... }:
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
        command = lib.concatStringsSep " " [
          "${pkgs.greetd.tuigreet}/bin/tuigreet"
          "--time"
          "--remember"
          "--sessions ${config.services.xserver.displayManager.sessionData.desktops}/share/wayland-sessions:${config.services.xserver.displayManager.sessionData.desktops}/share/xsessions"
          "--cmd ${hyprland-wrapper}/bin/hyprland-wrapper"
        ];
        user = "greeter";
      };
    };
  };

  # Below is required for some weird reason when using greetd with autologin
  users.groups.pschmitt = { };
}
