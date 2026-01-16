{
  lib,
  inputs,
  pkgs,
  ...
}:

let
  # xdphPkg = pkgs.master.xdg-desktop-portal-hyprland;
  # hyprlandPkg = pkgs.master.hyprland;
  hyprlandPkg = inputs.hyprland.packages.${pkgs.stdenv.hostPlatform.system}.hyprland;
  xdphPkg = inputs.hyprland.packages.${pkgs.stdenv.hostPlatform.system}.xdg-desktop-portal-hyprland;
in
{
  imports = [ inputs.hyprland.nixosModules.default ];

  nix.settings = {
    # Hyprland flake
    substituters = [ "https://hyprland.cachix.org" ];
    trusted-public-keys = [ "hyprland.cachix.org-1:a7pgxzMz7+chwVL3/pzj6jIBMioiJM7ypFP8PwtkuGc=" ];
  };

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

    uwsm = {
      enable = true;
      waylandCompositors.hyprland = {
        prettyName = "Hyprland (UWSM)";
        comment = "Hyprland compositor managed by UWSM";
        binPath = "${hyprlandPkg}/bin/Hyprland";
      };
    };
  };

  services.displayManager.defaultSession = lib.mkForce "hyprland-uwsm";

  # This essentially adds ~/bin to the PATH of systemd user services
  systemd.user.extraConfig =
    let
      paths = [
        "%h/bin"
        "%h/.local/bin"
        "/run/wrappers/bin"
        "/etc/profiles/per-user/%u/bin"
        "/nix/var/nix/profiles/default/bin"
        "/run/current-system/sw/bin"
      ];
    in
    ''
      DefaultEnvironment="PATH=${builtins.concatStringsSep ":" paths}:\$PATH"
    '';

  security.pam = {
    # fix for:
    # [ERR] Pam module "/etc/pam.d/hyprlock" does not exist! Falling back to "/etc/pam.d/su"
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
