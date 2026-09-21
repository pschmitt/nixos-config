{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  # pschmitt/obs-studio is ge2-only (its OBS Studio streaming/recording
  # setup) -- deliberately not added to profiles/laptop/noctalia.nix's shared
  # plugin list, which gk4 and x13 also pick up.
  noctaliaPlugins = inputs.noctalia-plugins.packages.${pkgs.stdenv.hostPlatform.system};
in
{
  imports = [
    ./hardware-configuration.nix

    # customizations
    # custom gdm monitor config
    ./gdm.nix
    ./wacom.nix
    ./falcon-sensor-vm.nix
    ./crash-diagnostics.nix
    ../../profiles/work/elgato-stream-deck.nix

    ../../profiles/roles/workstation.nix
    ../../profiles/roles/lan-mouse-peer.nix

    ../../services/initrd-luks-ssh-unlock.nix
  ];

  hardware.cattle = false;

  services.kmscon.config = {
    "xkb-keymap" = "${pkgs.custom-keymaps}/share/keymaps/custom/hhkb-de.xkb";
  };

  initrd.wifi = {
    enable = true;
    interfaceName = "wlp0s20f3";
  };

  # don't go to sleep when lid is closed
  services.logind.settings.Login = {
    HandleLidSwitchExternalPower = lib.mkForce "ignore";
    HandleLidSwitch = lib.mkForce "ignore";
  };

  # Enable networking
  networking = {
    hostName = "ge2";
    # Disable the firewall altogether.
    firewall.enable = false;
  };

  # ge2 uses UKIs with ~155 MB initrds, so /boot can only hold two
  # generations comfortably on its 512 MB EFI partition.
  boot.loader.systemd-boot.configurationLimit = lib.mkForce 1;

  home-manager.users.${config.mainUser.username} = { config, ... }: {
    programs.noctalia.settings = {
      plugin_settings = {
        "pschmitt/fan-control".alt_mode = true;
        "pschmitt/battery-icon".show_fan_controls = false;
        # OBS Studio bar/panel plugin -- ge2 only, see hosts/ge2/default.nix's
        # `noctaliaPlugins` comment above. Record/stream toggles hidden from the
        # panel by request; scene dropdown, virtual-camera and mute toggles stay.
        "pschmitt/obs-studio" = {
          panel_show_record_button = false;
          panel_show_stream_button = false;
          # home-manager/gui/obs-studio.nix's "obs-studio-custom" desktop entry
          # (our custom launch flags), not the plain `obs` binary this setting
          # defaults to.
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
      # Named bar-widget instance (see profiles/laptop/noctalia.nix's own
      # comment on why plugin widgets need one), placed right after the
      # sync-tray capsule -- i.e. to the right of its "tray" member -- in
      # bar.main.end. List-option merge order across modules isn't reliably
      # position-preserving, so this replaces the whole `end` list (mirroring
      # profiles/laptop/noctalia.nix's) rather than appending to it.
      widget."obs-studio".type = "pschmitt/obs-studio:bar";
      bar.main.end = lib.mkForce [
        "media"
        "group:sync-tray"
        "obs-studio"
        "group:volume"
        "group:notif-battery"
      ];
    };
    host.extraAutostartEntries = [
      "${config.home.profileDirectory}/share/applications/obs-studio-autostart.desktop"
    ];
    services.go-hass-agent.enableWorkCommands = true;

    # Declarative custom-buttons config for the plugin's panel (read-only,
    # same base-file convention as pschmitt/ha's ha.yaml) -- wraps the
    # existing obs-control verbs already bound to hyprland keys (see
    # home-manager/gui/hyprland/conf/keys.nix and pkgs/local/obs-control).
    xdg.configFile."noctalia/obs-studio.yaml" = {
      force = true;
      text = ''
        buttons:
          - label: BRB
            icon: coffee
            obs_control: brb
            bg: "#f4a340"
            fg: "#1a1200"
          - label: Webcam
            icon: camera
            obs_control: webcam
            bg: "#3b82f6"
            fg: "#ffffff"
          - label: Alt cam
            icon: rotate-clockwise
            obs_control: alt
            bg: "#8b5cf6"
            fg: "#ffffff"
          - label: Freeze
            icon: snowflake
            filter_source: Webcam
            filter_name: Freeze
            bg: "#38bdf8"
            fg: "#04232f"
          - label: Replay
            icon: repeat
            obs_control: replay
            bg: "#14b8a6"
            fg: "#06231e"
          - label: Thumbs up
            icon: thumb-up
            obs_control: thumbs-up
            bg: "#22c55e"
            fg: "#052e12"
          - label: Dislike
            icon: thumb-down
            obs_control: thumbs-down
            bg: "#ef4444"
            fg: "#2a0505"
          - label: Roomba
            icon: robot
            obs_cli: [item, toggle, -s, "📹 Webcam", roomba]
            bg: "#8d6e63"
            fg: "#ffffff"
      '';
    };

    # gk4 sits to the right of ge2.
    services.lan-mouse.peers = [
      {
        name = "gk4";
        position = "right";
      }
    ];
  };
}
