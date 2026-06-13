_: {
  services.elephant.enable = true;

  services.walker = {
    enable = true;
    systemd.enable = true;
    settings.theme = "nord";
    theme = {
      name = "nord";
      style = ''
        @define-color foreground #D8DEE9;
        @define-color background #24282F;
        @define-color surface #2E3440;
        @define-color overlay #3B4252;
        @define-color muted #4C566A;
        @define-color accent #88C0D0;

        * {
          all: unset;
        }

        window {
          background: transparent;
        }

        .box-wrapper {
          background: @background;
          border-radius: 12px;
          padding: 20px;
          border: 1px solid @overlay;
          box-shadow:
            0 19px 38px rgba(0, 0, 0, 0.5),
            0 15px 12px rgba(0, 0, 0, 0.3);
          color: @foreground;
          font-family: "ComicCode Nerd Font", monospace;
          font-size: 14px;
        }

        .search-container {
          background: @surface;
          border-radius: 6px;
          padding: 8px 12px;
          margin-bottom: 4px;
        }

        .input {
          color: @foreground;
          font-size: 15px;
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
          margin: 1px 0;
        }

        .item-box {
          padding: 6px 8px;
          border-radius: 6px;
        }

        child:selected .item-box,
        row:selected .item-box {
          background: @overlay;
        }

        .item-text {
          color: @foreground;
          font-weight: 500;
        }

        child:selected .item-text,
        row:selected .item-text {
          color: @accent;
        }

        .item-subtext {
          color: @muted;
          font-size: 0.85em;
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
          font-size: 12px;
          padding-top: 8px;
          border-top: 1px solid @overlay;
          margin-top: 4px;
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
