{ pkgs, ... }:
let
  target = "graphical-session.target";
in
{
  home.packages = [
    pkgs.wl-clipboard
  ];

  services.wl-clip-persist = {
    enable = true;
    # NOTE Setting the clipboardType to "both" causes issues with GTK apps such
    # nautilus and meld where text becomes impossible to select.
    # https://github.com/hyprwm/Hyprland/issues/2619
    clipboardType = "regular";
    systemdTargets = [ target ];
  };

  # Sync primary selection (selected text) → regular clipboard
  systemd.user.services.primary-to-clipboard = {
    Unit = {
      Description = "Sync Wayland primary selection to clipboard";
      After = [ target ];
      PartOf = [ target ];
    };
    Service = {
      ExecStart = "${pkgs.wl-clipboard}/bin/wl-paste --primary --watch ${pkgs.wl-clipboard}/bin/wl-copy";
      Restart = "on-failure";
    };
    Install.WantedBy = [ target ];
  };
}
