{
  config,
  pkgs,
  ...
}:
{
  environment.systemPackages = [
    pkgs.go-hass-agent
  ];

  sops.secrets = {
    "home-assistant/server" = { };
    "home-assistant/token".sopsFile = config.custom.sopsFile;
  };

  sops.templates."go-hass-agent.env" = {
    content = ''
      HASS_SERVER=${config.sops.placeholder."home-assistant/server"}
      HASS_TOKEN=${config.sops.placeholder."home-assistant/token"}
    '';
  };

  systemd.services.go-hass-agent = {
    enable = true;
    description = "A Home Assistant, native app for desktop/laptop devices.";
    documentation = [ "https://github.com/joshuar/go-hass-agent" ];
    after = [ "NetworkManager-wait-online.service" ];
    path = [
      config.custom.homeDirectory
      "/run/current-system/sw"
      "/etc/profiles/per-user/${config.custom.username}"
      pkgs.chrony
    ];

    # NOTE We probably need these 2 vars for playerctl
    # We might also need to restart the service once the user session has started
    environment = {
      XDG_RUNTIME_DIR = "/run/user/1000";
      DBUS_SESSION_BUS_ADDRESS = "unix:path=/run/user/1000/bus";
      # For the gui
      WAYLAND_DISPLAY = "wayland-1";
      DISPLAY = ":0";
    };

    serviceConfig = {
      User = "${config.custom.username}";
      EnvironmentFile = config.sops.templates."go-hass-agent.env".path;

      ExecStartPre = "${pkgs.go-hass-agent}/bin/go-hass-agent register --force --server=\"$HASS_SERVER\" --token=\"$HASS_TOKEN\"";

      # NOTE We can't use %E here since we are running as a system service
      # EnvironmentFile = "${config.custom.homeDirectory}/.config/go-hass-agent/secrets";
      ExecStart = "${pkgs.go-hass-agent}/bin/go-hass-agent run";

      Restart = "always";
      RestartSec = 5;
    };

    # For user services
    # wantedBy = [ "default.target" ];
    # For system services
    wantedBy = [ "multi-user.target" ];
  };
}
