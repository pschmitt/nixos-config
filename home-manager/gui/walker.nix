{ lib, pkgs, ... }:
let
  hyprlandSessionTarget = "hyprland-session.target";

  emojiList =
    pkgs.runCommand "elephant-emoji-list.txt"
      {
        buildInputs = [ pkgs.emoji-fzf ];
      }
      ''
        emoji-fzf --custom-aliases ${./walker/emoji-fzf-aliases.json} preview --prepend > $out
      '';

  elephantRbwUnlock = pkgs.writeShellApplication {
    name = "elephant-rbw-unlock";
    runtimeInputs = with pkgs; [
      coreutils
      rbw
    ];
    text = ''
      set -euo pipefail

      if rbw unlocked >/dev/null 2>&1
      then
        exit 0
      fi

      secret_file=/run/secrets/bitwarden/password
      pin_file="''${XDG_CONFIG_HOME:-$HOME/.config}/rbw/bin/.pin"
      pinentry="''${XDG_CONFIG_HOME:-$HOME/.config}/rbw/bin/pinentry-rbw"

      if [[ ! -r "$secret_file" || ! -x "$pinentry" ]]
      then
        exit 0
      fi

      mkdir -p "$(dirname "$pin_file")"
      printf '%s' "$(< "$secret_file")" > "$pin_file"
      rbw config set pinentry "$pinentry" >/dev/null
      rbw unlock >/dev/null
    '';
  };
in
{
  services.elephant.enable = true;

  xdg.configFile = {
    "elephant/menus/emoji.lua".source = ./walker/emoji.lua;
    "elephant/menus/obs-reaction.lua".source = ./walker/obs-reaction.lua;
    "elephant/menus/soundboard.lua".source = ./walker/soundboard.lua;
    "elephant/menus/soundboard-tts.lua".source = ./walker/soundboard-tts.lua;
    "elephant/emoji-list.txt".source = emojiList;
  };

  systemd.user.services = {
    walker.Unit = {
      After = [
        "wayland-wm-app-daemon.service"
        hyprlandSessionTarget
      ];
      Wants = [ "wayland-wm-app-daemon.service" ];
      PartOf = [ hyprlandSessionTarget ];
    };
    walker.Install.WantedBy = lib.mkForce [ hyprlandSessionTarget ];
    elephant = {
      Unit = {
        After = [ hyprlandSessionTarget ];
        PartOf = [ hyprlandSessionTarget ];
        X-Restart-Triggers = [
          "${./walker/emoji.lua}"
          "${./walker/obs-reaction.lua}"
          "${./walker/soundboard.lua}"
          "${./walker/soundboard-tts.lua}"
          "${emojiList}"
        ];
      };
      Install.WantedBy = lib.mkForce [ hyprlandSessionTarget ];
      Service.ExecStartPre = "${elephantRbwUnlock}/bin/elephant-rbw-unlock";
    };
  };

  services.walker = {
    enable = true;
    systemd.enable = true;
    settings = {
      app_launch_prefix = "uwsm app -- ";
      keybinds.quick_activate = [
        "alt 1"
        "alt 2"
        "alt 3"
        "alt 4"
        "alt 5"
      ];

      theme = "justgray";
      modules = [ { name = "menus"; } ];
      providers.prefixes = [
        {
          prefix = ";";
          provider = "providerlist";
        }
        {
          prefix = ">";
          provider = "runner";
        }
        {
          prefix = "/";
          provider = "files";
        }
        {
          prefix = ".";
          provider = "menus:emoji";
        }
        {
          prefix = "~";
          provider = "symbols";
        }
        {
          prefix = "!";
          provider = "todo";
        }
        {
          prefix = "$";
          provider = "windows";
        }
        {
          prefix = ",";
          provider = "menus:soundboard-tts";
        }
      ];
      providers.actions = {
        "menus:emoji" = [
          {
            action = "default";
            bind = "Return";
            default = true;
            after = "Close";
          }
          {
            action = "toggle-pin";
            bind = "ctrl p";
            label = "📌 Pin / Unpin";
            after = "AsyncReload";
          }
        ];
        "menus:obs-reaction" = [
          {
            action = "default";
            bind = "Return";
            default = true;
            after = "Close";
          }
        ];
        "menus:soundboard" = [
          {
            action = "default";
            bind = "Return";
            default = true;
            after = "Close";
          }
          {
            action = "tts-en";
            bind = "ctrl e";
            label = "🗣️ English";
            after = "Close";
          }
          {
            action = "tts-de";
            bind = "ctrl d";
            label = "🗣️ Deutsch";
            after = "Close";
          }
          {
            action = "tts-ha";
            bind = "ctrl h";
            label = "☁️ HA Cloud";
            after = "Close";
          }
        ];
        "menus:soundboard-tts" = [
          {
            action = "default";
            bind = "Return";
            default = true;
            after = "Close";
          }
          {
            action = "tts-en";
            bind = "ctrl e";
            label = "🗣️ English";
            after = "Close";
          }
          {
            action = "tts-de";
            bind = "ctrl d";
            label = "🗣️ Deutsch";
            after = "Close";
          }
          {
            action = "tts-ha";
            bind = "ctrl h";
            label = "☁️ HA Cloud";
            after = "Close";
          }
        ];
      };
    };
    theme = {
      name = "justgray";
      style = ''
        @define-color foreground #C7CCD1;
        @define-color background #24282F;
        @define-color surface #2E2E2E;
        @define-color overlay #383838;
        @define-color muted #717171;
        @define-color accent #A6A6A6;

        * {
          all: unset;
        }

        window {
          background: transparent;
        }

        .box-wrapper {
          background: @background;
          border-radius: 12px;
          min-width: 800px;
          padding: 20px;
          border: 1px solid @overlay;
          box-shadow:
            0 19px 38px rgba(0, 0, 0, 0.5),
            0 15px 12px rgba(0, 0, 0, 0.3);
          color: @foreground;
          font-family: "ComicCode Nerd Font", monospace;
          font-size: 17px;
        }

        .search-container {
          background: @surface;
          border-radius: 6px;
          padding: 10px 14px;
          margin-bottom: 8px;
        }

        .input {
          color: @foreground;
          font-size: 18px;
        }

        .input placeholder {
          color: @muted;
          opacity: 0.8;
        }

        scrollbar {
          opacity: 0;
        }

        child {
          border-radius: 6px;
          margin: 2px 0;
        }

        .item-box {
          padding: 8px 10px;
          border-radius: 6px;
        }

        .normal-icons {
          -gtk-icon-size: 24px;
        }

        .large-icons {
          -gtk-icon-size: 42px;
        }

        .item-image {
          margin-right: 10px;
        }

        .item-image-text {
          font-size: 34px;
        }

        child:selected .item-box,
        row:selected .item-box {
          background: @overlay;
        }

        .item-text {
          color: @foreground;
          font-weight: 500;
          font-size: 20px;
        }

        child:selected .item-text,
        row:selected .item-text {
          color: @accent;
        }

        .item-subtext {
          color: @muted;
          font-size: 0.95em;
        }

        .item-quick-activation {
          color: @muted;
        }

        child:selected .item-quick-activation,
        row:selected .item-quick-activation {
          color: @accent;
        }

        .keybinds {
          color: @muted;
          font-size: 14px;
          padding-top: 10px;
          border-top: 1px solid @overlay;
          margin-top: 6px;
        }

        .error {
          background: rgba(191, 97, 106, 0.4);
          border-radius: 4px;
          padding: 8px;
          color: @foreground;
        }

        .placeholder,
        .elephant-hint {
          color: @muted;
        }
      '';
    };
  };
}
