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
    "home-assistant/server" = {
      owner = config.mainUser.username;
    };
    "home-assistant/token" = {
      inherit (config.custom) sopsFile;
      owner = config.mainUser.username;
    };
    "home-assistant/mqtt/host" = { };
    "home-assistant/mqtt/username".sopsFile = config.custom.sopsFile;
    "home-assistant/mqtt/password".sopsFile = config.custom.sopsFile;
  };

  sops.templates."go-hass-agent.env" = {
    content = ''
      # DEBUG
      GOHASSAGENT_LOGLEVEL=debug
      HASS_SERVER=${config.sops.placeholder."home-assistant/server"}
      HASS_TOKEN=${config.sops.placeholder."home-assistant/token"}
      MQTT_SERVER=${config.sops.placeholder."home-assistant/mqtt/host"}
      MQTT_USERNAME=${config.sops.placeholder."home-assistant/mqtt/username"}
      MQTT_PASSWORD=${config.sops.placeholder."home-assistant/mqtt/password"}
    '';
    owner = config.systemd.services.go-hass-agent.serviceConfig.User;
  };

  systemd.services.go-hass-agent = {
    enable = true;
    description = "A Home Assistant, native app for desktop/laptop devices.";
    documentation = [ "https://github.com/joshuar/go-hass-agent" ];
    after = [ "NetworkManager-wait-online.service" ];
    path = [
      "/etc/profiles/per-user/${config.mainUser.username}"
      "/run/current-system/sw"
      config.mainUser.homeDirectory
      pkgs.chrony
      pkgs.coreutils
      pkgs.gawk
      pkgs.gnugrep
      pkgs.smartmontools
      pkgs.util-linux
    ];

    # NOTE We probably need these 2 vars for playerctl
    # We might also need to restart the service once the user session has started
    environment = {
      XDG_RUNTIME_DIR = "/run/user/1000";
      DBUS_SESSION_BUS_ADDRESS = "unix:path=/run/user/1000/bus";
    };

    serviceConfig =
      let
        goHassAgent = "${pkgs.go-hass-agent}/bin/go-hass-agent";
      in
      {
        User = "${config.mainUser.username}";
        EnvironmentFile = config.sops.templates."go-hass-agent.env".path;

        # Alternatively we could use security.wrappers:
        # security.wrappers.go-hass-agent = {
        #   source = goHassBin;
        #   capabilities = "cap_sys_rawio,cap_sys_admin,cap_mknod,cap_dac_override=+ep";
        #   owner = config.mainUser.username;
        #   group = "users";
        # };
        AmbientCapabilities = [
          "CAP_DAC_OVERRIDE"
          "CAP_MKNOD"
          "CAP_SYS_ADMIN"
          "CAP_SYS_RAWIO"
        ];

        ExecStartPre = [
          # FIXME The env vars are not expanded here for some reason, if not
          # run wrapped in bash
          "${pkgs.bash}/bin/bash -c '${goHassAgent} register --server=$HASS_SERVER --token=$HASS_TOKEN'"
          "${pkgs.bash}/bin/bash -c '${goHassAgent} config --mqtt-server=$MQTT_SERVER --mqtt-user=$MQTT_USERNAME --mqtt-password=$MQTT_PASSWORD --mqtt-topic-prefix=homeassistant'"
        ];

        # NOTE We can't use %E here since we are running as a system service
        # EnvironmentFile = "${config.mainUser.homeDirectory}/.config/go-hass-agent/secrets";
        ExecStart = "${goHassAgent} run";

        Restart = "always";
        RestartSec = 5;
      };

    # For user services
    # wantedBy = [ "default.target" ];
    # For system services
    wantedBy = [ "multi-user.target" ];
  };
}
