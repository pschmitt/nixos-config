{
  lib,
  inputs,
  config,
  pkgs,
  ...
}:

let
  hyprlandPkg = inputs.hyprland.packages.${pkgs.system}.hyprland;
  # hyprlandPkg = pkgs.hyprland;
  xdphPkg = inputs.xdph.packages.${pkgs.system}.xdg-desktop-portal-hyprland;
  # xdphPkg = pkgs.xdg-desktop-portal-hyprland;
  hypridlePkg = inputs.hypridle.packages.${pkgs.system}.hypridle;
  hyprlockPkg = inputs.hyprlock.packages.${pkgs.system}.hyprlock;
in
{
  imports = [
    (import ./greetd.nix {
      inherit
        lib
        config
        pkgs
        hyprlandPkg
        ;
    })
  ];

  nix.settings = {
    # Hyprland flake
    substituters = [ "https://hyprland.cachix.org" ];
    trusted-public-keys = [ "hyprland.cachix.org-1:a7pgxzMz7+chwVL3/pzj6jIBMioiJM7ypFP8PwtkuGc=" ];
  };

  environment.sessionVariables = {
    # Setting MOZ_ENABLE_WAYLAND will lead to a fullscreen sharing indicator
    # when screensharing
    # https://bugzilla.mozilla.org/show_bug.cgi?id=1628431
    # MOZ_ENABLE_WAYLAND = "1";
    MOZ_USE_XINPUT2 = "1";

    # Fix cursor not showing up on some outputs
    # https://www.reddit.com/r/NixOS/comments/105f4e0/invisible_cursor_on_hyprland/
    WLR_NO_HARDWARE_CURSORS = "1";
  };

  environment.systemPackages = with pkgs; [
    # Hyprland
    hyprlandPkg

    # Notifications
    libnotify # notify-send
    mako

    # lock
    chayang # gradually dim screen
    swayidle
    # swaylock
    swaylock-effects
    hypridlePkg
    hyprlockPkg

    # waybar
    networkmanagerapplet
    playerctl
    waybar
    wttrbar

    # screenshots
    grim
    slurp
    swappy
    wf-recorder

    # clipboard
    # FIXME cliphist 0.5.0 is broken, 0.6.1 is in master as of 2024-10-16
    # See: https://nixpk.gs/pr-tracker.html?pr=348887
    # https://github.com/NixOS/nixpkgs/issues/348819
    master.cliphist
    # cliphist
    wl-clip-persist
    wl-clipboard

    # services
    polkit_gnome
    xorg.xhost

    # tools
    brightnessctl
    hyprpaper # wallpaper
    hyprpicker
    kanshi
    shikane # kanshi alternative, rust
    wev
    wlogout
    wofi
  ];

  fonts.enableDefaultPackages = true;

  hardware.graphics.enable = lib.mkForce true;

  programs = {
    hyprland = {
      enable = true;
      package = hyprlandPkg;
      portalPackage = xdphPkg;
    };

    hyprlock = {
      enable = true;
      package = hyprlockPkg;
    };

    waybar.enable = true;
    nm-applet.enable = true;

    uwsm = {
      enable = true;

      waylandCompositors = {
        hyprland = {
          prettyName = "Hyprland";
          comment = "Hyprland compositor managed by UWSM";
          binPath = "/run/current-system/sw/bin/Hyprland";
        };
      };
    };
  };

  services = {
    acpid = {
      enable = true;
      logEvents = true;
      lidEventCommands = ''
        # NOTE We want to expand the args here, so we don't quote "$@"
        /run/wrappers/bin/sudo -u ${config.custom.username} \
          ${config.custom.homeDirectory}/.config/hypr/bin/lid-event.sh $@
      '';
    };

    hypridle = {
      enable = true;
      package = hypridlePkg;
    };
  };

  security = {
    # NOTE Mitigate hyprland crapping its pants under high load (nixos-rebuild)
    # https://nixos.wiki/wiki/Sway
    pam.loginLimits = [
      {
        domain = "@users";
        item = "rtprio";
        type = "-";
        value = 1;
      }
    ];
  };
}

# vim: set ft=nix et ts=2 sw=2 :
