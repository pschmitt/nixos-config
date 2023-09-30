# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{ inputs, config, pkgs, ... }:

{
  nix.settings = {
    # Hyprland flake
    substituters = [ "https://hyprland.cachix.org" ];
    trusted-public-keys = [
      "hyprland.cachix.org-1:a7pgxzMz7+chwVL3/pzj6jIBMioiJM7ypFP8PwtkuGc="
    ];
  };

  environment.sessionVariables = rec {
    # GTK_THEME = "Adwaita:dark";
    # Setting MOZ_ENABLE_WAYLAND will lead to a fullscreen sharing indicator
    # when screensharing
    # https://bugzilla.mozilla.org/show_bug.cgi?id=1628431
    # MOZ_ENABLE_WAYLAND = "1";
    MOZ_USE_XINPUT2 = "1";
  };

  environment.systemPackages = with pkgs; [
    # Hyprland
    inputs.hyprland.packages.${pkgs.system}.hyprland

    polkit_gnome
    xorg.xhost
    kitty # default terminal (the one used by the default config)

    brightnessctl
    cliphist
    foot
    gnome.eog
    gnome.nautilus
    gnome.seahorse
    gnome.sushi
    grim
    # NOTE gtklock is also installed with home-manager so that we get reliable
    # symlinks in /etc/profiles/per-user/pschmitt/lib/gtklock/
    gtklock
    gtklock-playerctl-module
    gtklock-userinfo-module
    hyprpaper
    lemonade
    libnotify
    mako
    networkmanagerapplet
    nwg-displays
    playerctl
    slurp
    swappy
    swayidle
    unstable.waybar
    unstable.wl-clip-persist
    wayvnc
    wl-clipboard
    wlogout
    wlr-randr
    wofi
    wofi-emoji
    wlrctl
    wdisplays
    wtype
    ydotool

    # Theming
    adwaita-qt
    adwaita-qt6
    bibata-cursors
    colloid-gtk-theme
    colloid-icon-theme
    colloid-kde
    glib # gsettings
    gnome.adwaita-icon-theme
    gnome.gnome-themes-extra
    libadwaita
    lxappearance
    qt5ct

    # NOTE We could use the below fake package to write the wayland-session file
    # We'd PROBABLY (lol) only need to add it to:
    # services.xserver.displayManager.sessionPackages sessionPackages
    #
    # (writeTextFile {
    #   name = "hyprland-wrapped.desktop";
    #   destination = "/share/wayland-sessions/hyprland-wrapped.desktop";
    #   text = ''
    #     [Desktop Entry]
    #     Name=Hyprland (wrapped)
    #     Comment=Hyprland (wrapped)
    #     Exec=${config.users.users.pschmitt.home}/.config/hypr/bin/hyprland-wrapped.sh
    #     Type=Application
    #   '';
    # })
  ];

  fonts.enableDefaultFonts = true;

  hardware.opengl.enable = true;

  programs = {
    dconf.enable = true; # also set by programs.hyprland.enable = true;
    xwayland.enable = true; # also set by programs.hyprland.enable = true;

    # # Hyprland
    # # Using NixOS 23.05's programs.hyprland results in xdph 0.3.0 being used
    # hyprland = {
    #   enable = true;
    #   # comment out line below to use the regular (non-flake) Hyprland version
    #   # package = pkgs.hyprland;
    #   package = hyprland-flake.packages.${pkgs.system}.hyprland;
    #   # NOTE portalPackage is an unstable *option*
    #   # portalPackage = unstable.xdg-desktop-portal-hyprland;
    # };
  };

  services = {
    # Required by gtklock-userinfo-module
    accounts-daemon.enable = true;

    xserver = {
      # Enable touchpad support (enabled by default in most desktopManager).
      libinput.enable = true; # also set by programs.hyprland.enable = true;
      displayManager.sessionPackages = [
        inputs.hyprland.packages.${pkgs.system}.hyprland
      ]; # also set by programs.hyprland.enable = true;
      displayManager.session = [{
        manage = "desktop";
        name = "hyprland-wrapped";
        start = ''
          /home/pschmitt/.config/hypr/bin/hyprland-wrapped.sh &
          waitPID=$!
        '';
      }];
    };
  };

  security = {
    polkit.enable = true; # also set by programs.hyprland.enable = true;
    # Enable gtk lock pam auth
    pam.services.gtklock = { };
  };

  systemd = {
    user.targets.hyprland-session = {
      description = "Hyprland compositor session";
      documentation = [ "man:systemd.special(7)" ];
      bindsTo = [ "graphical-session.target" ];
      wants = [ "graphical-session-pre.target" ];
      after = [ "graphical-session-pre.target" ];
    };
    user.services.polkit-gnome-authentication-agent-1 = {
      description = "polkit-gnome-authentication-agent-1";
      wantedBy = [ "graphical-session.target" ];
      wants = [ "graphical-session.target" ];
      after = [ "graphical-session.target" ];
      serviceConfig = {
        Type = "simple";
        ExecStart =
          "${pkgs.polkit_gnome}/libexec/polkit-gnome-authentication-agent-1";
        Restart = "on-failure";
        RestartSec = 1;
        TimeoutStopSec = 10;
      };
    };
  };

  # XDG Portals
  xdg = {
    autostart.enable = true;
    portal = {
      enable = true; # also set by programs.hyprland.enable = true;
      xdgOpenUsePortal = true;
      extraPortals = with pkgs; [
        inputs.xdph.packages.${pkgs.system}.xdg-desktop-portal-hyprland
        # xdg-desktop-portal-gtk
        # unstable.xdg-desktop-portal-hyprland
      ];
    };
  };
}

# vim: set ft=nix et ts=2 sw=2 :
