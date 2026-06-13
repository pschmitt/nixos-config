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

        #window,
        #box,
        #aiScroll,
        #aiList,
        #search,
        #password,
        #input,
        #prompt,
        #clear,
        #typeahead,
        #list,
        child,
        scrollbar,
        slider,
        #item,
        #text,
        #label,
        #bar,
        #sub,
        #activationlabel {
          all: unset;
        }

        #cfgerr {
          background: rgba(191, 97, 106, 0.4);
          margin-top: 20px;
          padding: 8px;
          font-size: 1.2em;
        }

        #window {
          color: @foreground;
          font-family: "ComicCode Nerd Font", monospace;
          font-size: 14px;
        }

        #box {
          border-radius: 10px;
          background: @background;
          padding: 20px;
          border: 1px solid @overlay;
          box-shadow:
            0 19px 38px rgba(0, 0, 0, 0.5),
            0 15px 12px rgba(0, 0, 0, 0.3);
        }

        #search {
          background: @surface;
          border-radius: 6px;
          padding: 8px 12px;
        }

        #prompt {
          margin-right: 10px;
          color: @muted;
        }

        #clear {
          color: @muted;
        }

        #input {
          background: none;
          color: @foreground;
          font-size: 15px;
        }

        #input placeholder {
          color: @muted;
          opacity: 0.8;
        }

        #typeahead {
          color: @muted;
        }

        child {
          padding: 6px 8px;
          border-radius: 6px;
          margin: 1px 0;
        }

        child:selected,
        child:hover {
          background: @overlay;
        }

        child:selected #label {
          color: @accent;
        }

        #icon {
          margin-right: 10px;
        }

        #label {
          color: @foreground;
          font-weight: 500;
        }

        #sub {
          color: @muted;
          font-size: 0.8em;
        }

        #activationlabel {
          color: @muted;
        }

        #bar {
          background: @surface;
          border-radius: 4px;
          margin-top: 8px;
          padding: 4px 8px;
        }

        .activation #activationlabel {
          color: @accent;
        }

        .activation #text,
        .activation #icon,
        .activation #search {
          opacity: 0.5;
        }

        .aiItem {
          padding: 10px;
          border-radius: 6px;
          color: @foreground;
          background: @surface;
        }

        .aiItem.user {
          padding-left: 0;
          padding-right: 0;
        }

        .aiItem.assistant {
          background: @overlay;
        }
      '';
    };
  };
}
