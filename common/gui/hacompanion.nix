{
  inputs,
  config,
  pkgs,
  ...
}:
{
  environment.systemPackages = [
    inputs.hacompanion.packages.${pkgs.system}.hacompanion
  ];

  systemd.services.hacompanion = {
    enable = true;
    description = "Home Assistant Companion application";
    documentation = [ "https://github.com/tobias-kuendig/hacompanion" ];
    after = [ "NetworkManager-wait-online.service" ];
    path = [
      "${config.custom.homeDirectory}"
      "/run/current-system/sw"
      "/etc/profiles/per-user/${config.custom.username}"
    ];

    # NOTE We probably need these 2 vars for playerctl
    # We might also need to restart the service once the user session has started
    environment = {
      XDG_RUNTIME_DIR = "/run/user/1000";
      DBUS_SESSION_BUS_ADDRESS = "unix:path=/run/user/1000/bus";
    };

    serviceConfig = {
      User = "${config.custom.username}";
      # NOTE We can't use %E here since we are running as a system service
      EnvironmentFile = "${config.custom.homeDirectory}/.config/hacompanion/secrets";
      ExecStart = "${pkgs.hacompanion}/bin/hacompanion -quiet -config ~/.config/hacompanion/hacompanion.toml";

      Restart = "always";
      RestartSec = 5;
    };

    # For user services
    # wantedBy = [ "default.target" ];
    # For system services
    wantedBy = [ "multi-user.target" ];
  };
}
