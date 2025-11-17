{
  lib,
  inputs,
  config,
  pkgs,
  ...
}:

let
  hyprlandPkg = inputs.hyprland.packages.${pkgs.stdenv.hostPlatform.system}.hyprland;
  # hyprlandPkg = pkgs.master.hyprland;

  # xdphPkg = inputs.hyprland.packages.${pkgs.stdenv.hostPlatform.system}.xdg-desktop-portal-hyprland;
  xdphPkg = pkgs.master.xdg-desktop-portal-hyprland;

  # hypridlePkg = inputs.hypridle.packages.${pkgs.stdenv.hostPlatform.system}.hypridle;
  hypridlePkg = pkgs.master.hypridle;

  # hyprlockPkg = inputs.hyprlock.packages.${pkgs.stdenv.hostPlatform.system}.hyprlock;
  hyprlockPkg = pkgs.master.hyprlock;
in
{
  imports = [ inputs.hyprland.nixosModules.default ];

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

    # noctalia-shell
    # inputs.noctalia.packages.${pkgs.stdenv.hostPlatform.system}.default

    # screenshots
    grim
    (pkgs.writeShellScriptBin "grim-hyprland" ''
      exec -a $0 ${inputs.grim-hyprland.packages.${pkgs.stdenv.hostPlatform.system}.default}/bin/grim "$@"
    '')
    slurp
    swappy
    wayfreeze
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
    hints
    hyprpaper # wallpaper
    hyprpicker
    kanshi
    shikane # kanshi alternative, rust
    waypoint
    wev
    wlogout
    wofi
  ];

  fonts.enableDefaultPackages = true;

  hardware.graphics.enable = lib.mkForce true;

  programs = {
    hyprland = {
      enable = true;
      withUWSM = true;
      package = hyprlandPkg;
      portalPackage = xdphPkg;
    };

    # FIXME This fails with .nm-applet-wrap[16214]: cannot open display:
    # and uwsm is already starting it (app-nm\\x2dapplet@autostart.service)
    # nm-applet.enable = true;
  };

  services.displayManager.defaultSession = lib.mkForce "hyprland-uwsm";

  # This essentially adds ~/bin to the PATH of systemd user services
  systemd.user.extraConfig = ''
    DefaultEnvironment="PATH=%h/bin:%h/.local/bin:/run/wrappers/bin:/etc/profiles/per-user/%u/bin:/nix/var/nix/profiles/default/bin:/run/current-system/sw/bin:$PATH"
  '';

  services = {
    acpid = {
      enable = true;
      logEvents = true;
      lidEventCommands = ''
        # NOTE We want to expand the args here, so we don't quote "$@"
        /run/wrappers/bin/sudo -u ${config.custom.username} \
          ${config.custom.homeDirectory}/.config/hypr/bin/lid-event.sh $@
        # DIRTYFIX This a workaround for the the sshfs mounts being messed up
        systemctl restart netbird-netbird-io.service
      '';
    };
  };

  security.pam = {
    # fix [ERR] Pam module "/etc/pam.d/hyprlock" does not exist! Falling back to "/etc/pam.d/su"
    services.hyprlock = { };
    # NOTE Mitigate hyprland crapping its pants under high load (nixos-rebuild)
    # https://nixos.wiki/wiki/Sway
    loginLimits = [
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
