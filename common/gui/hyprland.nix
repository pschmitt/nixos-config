# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

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

  hyprland-wrapper = (
    pkgs.writeTextFile {
      name = "hyprland-wrapper";
      destination = "/bin/hyprland-wrapper";
      executable = true;
      text = builtins.readFile ./hyprland-wrapper.sh;
    }
  );

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
        hyprland-wrapper
        ;
    })
  ];

  # inherit (import ./greetd.nix { inherit pkgs hyprlandPkg hyprland-wrapper; });

  nix.settings = {
    # Hyprland flake
    substituters = [ "https://hyprland.cachix.org" ];
    trusted-public-keys = [ "hyprland.cachix.org-1:a7pgxzMz7+chwVL3/pzj6jIBMioiJM7ypFP8PwtkuGc=" ];
  };

  environment.sessionVariables = {
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
    hyprland-wrapper

    # Notifications
    libnotify # notify-send
    mako

    # lock
    chayang # gradually dim screen
    (pkgs.writeShellScriptBin "gtklock-with-modules" ''
      ${pkgs.gtklock}/bin/gtklock \
        --modules ${pkgs.gtklock-userinfo-module}/lib/gtklock/userinfo-module.so \
        --modules ${pkgs.gtklock-playerctl-module}/lib/gtklock/playerctl-module.so \
        "$@"
    '')
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
    cliphist
    wl-clip-persist
    wl-clipboard

    # services
    polkit_gnome
    xorg.xhost

    # tools
    brightnessctl
    hyprpaper # wallpaper
    hyprpicker-git
    kanshi
    shikane # kanshi alternative, rust
    wev
    wlogout
    wofi

    # NOTE We could use the below fake package to write the wayland-session file
    # We'd PROBABLY (lol) only need to add it to:
    # services.xserver.displayManager.sessionPackage
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

    # Hyprland
    # hyprland = {
    #   enable = true;
    #   package = hyprlandPkg;
    #   portalPackage = xdphPkg;
    # };
  };

  services = {
    # Required by gtklock-userinfo-module
    accounts-daemon.enable = true;

    acpid = {
      enable = true;
      logEvents = true;
      lidEventCommands = ''
        # NOTE We want to expand the args here, so we don't quote "$@"
        /run/wrappers/bin/sudo -u ${config.custom.username} \
          ${config.custom.homeDirectory}/.config/hypr/bin/lid-event.sh $@
      '';
    };

    # below is also set by programs.hyprland.enable = true;
    displayManager.sessionPackages = [ hyprlandPkg ];

    xserver = {
      displayManager.session = [
        {
          manage = "desktop";
          name = "hyprland-wrapper";
          # FIXME Do we even still need this? The wrapper does not do all
          # that much anymore...
          start = builtins.readFile ./hyprland-wrapper.sh;
        }
      ];
    };
  };

  security = {
    # Enable gtk lock pam auth
    pam.services.gtklock = { };
    pam.services.swaylock = { };
    pam.services.hyprlock = { };
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

  systemd = {
    user.targets.hyprland-session = {
      description = "Hyprland compositor session";
      documentation = [ "man:systemd.special(7)" ];
      bindsTo = [ "graphical-session.target" ];
      wants = [ "graphical-session-pre.target" ];
      after = [ "graphical-session-pre.target" ];
    };
  };

  # XDG Portals
  xdg = {
    autostart.enable = true;
    portal = {
      enable = true; # also set by programs.hyprland.enable = true;
      xdgOpenUsePortal = true;
      extraPortals = [ xdphPkg ];
      # https://www.reddit.com/r/NixOS/comments/184hbt6/changes_to_xdgportals/
      # NOTE If you simply want to keep the behaviour in < 1.17, which uses the first
      # portal implementation found in lexicographical order, use the following:
      # xdg.portal.config.common.default = "*";
      config.common.default = "*";
      # FIXME xdph does not ship any share/xdg-desktop-portal/*.conf file
      # but share/xdg-desktop-portal/portals/hyprland.portal
      # configPackages = [ xdphPkg ];
    };
  };
}
# vim: set ft=nix et ts=2 sw=2 :
