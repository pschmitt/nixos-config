{ pkgs, ... }:
let
  emojiList =
    pkgs.runCommand "elephant-emoji-list.txt"
      {
        buildInputs = [ pkgs.emoji-fzf ];
      }
      ''
        emoji-fzf --custom-aliases ${./walker/emoji-fzf-aliases.json} preview --prepend > $out
      '';
in
{
  services.elephant.enable = true;

  xdg.configFile."elephant/menus/emoji.lua".source = ./walker/emoji.lua;
  xdg.configFile."elephant/emoji-list.txt".source = emojiList;

  systemd.user.services.elephant.Unit.X-Restart-Triggers = [
    "${./walker/emoji.lua}"
    "${emojiList}"
  ];

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
      ];
      theme = "justgray";
      modules = [ { name = "menus"; } ];
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
