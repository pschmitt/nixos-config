# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{ inputs, config, pkgs, ... }:

let
  # hyprlandPkg = inputs.hyprland.packages.${pkgs.system}.hyprland-nvidia;
  # hyprlandPkg = inputs.hyprland.packages.${pkgs.system}.hyprland;
  hyprlandPkg = pkgs.hyprland;

  xdphPkg = inputs.xdph.packages.${pkgs.system}.xdg-desktop-portal-hyprland;
  # xdphPkg = pkgs.xdg-desktop-portal-hyprland;

in
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
    hyprlandPkg

    polkit_gnome
    xorg.xhost
    kitty # default terminal (the one used by the default config)

    alacritty
    brightnessctl
    cliphist
    foot
    gnome.eog
    gnome.evince
    gnome.gnome-font-viewer
    gnome.file-roller
    gnome.nautilus
    gnome.seahorse
    gnome.sushi
    grim
    chayang # gradually dim screen
    (pkgs.stdenv.mkDerivation {
      name = "gtklock-with-modules";
      src = pkgs.writeShellScript "gtklock-with-modules" ''
        ${pkgs.gtklock}/bin/gtklock \
          --modules ${pkgs.gtklock-userinfo-module}/lib/gtklock/userinfo-module.so \
          --modules ${pkgs.gtklock-playerctl-module}/lib/gtklock/playerctl-module.so \
          "$@"
      '';

      phases = [ "installPhase" ];

      installPhase = ''
        mkdir -p $out/bin
        cp $src $out/bin/gtklock-with-modules
        chmod +x $out/bin/gtklock-with-modules
      '';
    })
    hyprpaper
    lemonade
    libnotify
    mako
    networkmanagerapplet
    nwg-displays
    playerctl
    remmina
    slurp
    swappy
    swayidle
    waybar
    wayvnc
    wdisplays
    wl-clip-persist
    wl-clipboard
    wlogout
    wlr-randr
    wlrctl
    wofi
    wofi-emoji
    wtype
    ydotool

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

  fonts.enableDefaultPackages = true;

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
        hyprlandPkg
      ]; # also set by programs.hyprland.enable = true;
      displayManager.session = [{
        manage = "desktop";
        name = "hyprland-wrapped";
        # FIXME Do we even still need this? The wrapper does not do all
        # that much anymore...
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
      extraPortals = [ xdphPkg ];
    };
  };
}

# vim: set ft=nix et ts=2 sw=2 :
