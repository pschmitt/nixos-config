{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  noctaliaPlugins = inputs.noctalia-plugins.packages.${pkgs.stdenv.hostPlatform.system};
in
{
  home-manager.users.${config.mainUser.username} = _: {
    programs.noctalia.settings = {
      plugin_settings = {
        "pschmitt/fan-control".alt_mode = true;
        "pschmitt/battery-icon".show_fan_controls = false;
        "pschmitt/obs-studio" = {
          panel_show_record_button = false;
          panel_show_stream_button = false;
          mic_input_name = "mic";
          launch_command = "gtk-launch obs-studio-custom";
        };
      };
      plugins = {
        enabled = [ "pschmitt/obs-studio" ];
        source = [
          {
            name = "pschmitt-obs-studio";
            kind = "path";
            location = "${noctaliaPlugins.noctalia-obs-studio}/share/noctalia-plugins";
            enabled = true;
          }
        ];
      };
      widget."obs-studio".type = "pschmitt/obs-studio:bar";
      bar.main.end = lib.mkForce [
        "media"
        "group:sync-tray"
        "obs-studio"
        "group:volume"
        "group:notif-battery"
      ];
    };

    xdg.configFile."noctalia/obs-studio.yaml" = {
      force = true;
      text = ''
        buttons:
          - label: BRB
            icon: coffee
            command: [obs-control, brb]
            active_scene: "🚬 brb"
            bg: "#f4a340"
            fg: "#1a1200"
          - label: Webcam
            icon: camera
            command: [obs-control, webcam]
            active_scene: "📹 Webcam"
            bg: "#3b82f6"
            fg: "#ffffff"
          - label: Alt cam
            icon: rotate-clockwise
            command: [obs-control, alt]
            active_scene: "👣 Alternative Camera"
            bg: "#8b5cf6"
            fg: "#ffffff"
          - label: Freeze
            icon: snowflake
            command: [obs-control, toggle-freeze]
            state_filter_source: Webcam
            state_filter_name: Freeze
            bg: "#38bdf8"
            fg: "#04232f"
          - label: Replay
            icon: repeat
            command: [obs-control, replay]
            active_scene: "🔄 Replay"
            bg: "#14b8a6"
            fg: "#06231e"
          - label: Thumbs up
            icon: thumb-up
            command: [obs-control, thumbs-up]
            bg: "#22c55e"
            fg: "#052e12"
          - label: Dislike
            icon: thumb-down
            command: [obs-control, thumbs-down]
            bg: "#ef4444"
            fg: "#2a0505"
          - label: Roomba
            icon: robot
            obs_cli: [item, toggle, -s, "📹 Webcam", roomba]
            bg: "#8d6e63"
            fg: "#ffffff"
      '';
    };
  };
}
