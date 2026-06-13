{
  config,
  hostname,
  lib,
  pkgs,
  ...
}:
let
  # Attach to (or create) the main tmux session. Replaces the zhj
  # `tmux::attach` zsh function so this does not depend on the yadm setup.
  tmuxAttach = pkgs.writeShellScript "tmux-attach" ''
    exec ${pkgs.tmux}/bin/tmux -u new -A -D -s main
  '';

  # Connect to the remote tmux session on fnuc without relying on zsh wrappers.
  remoteTmuxFnuc = pkgs.writeShellScript "remote-tmux-fnuc" ''
    exec ${pkgs.openssh}/bin/ssh -t f \
      '${pkgs.tmux}/bin/tmux -u new -A -s main'
  '';

  kittyTmuxSession = pkgs.writeText "kitty-tmux.session" ''
    launch --title ${hostname} ${tmuxAttach}
    new_tab fnuc
    launch --title fnuc ${remoteTmuxFnuc}
    focus_tab 0
  '';
in
{
  home.packages = with pkgs; [
    nextcloud-client
  ];

  xdg = {
    desktopEntries = {
      tmux = {
        name = "tmux@local";
        comment = "Start kitty with local tmux";
        # FIXME We *should* be able to use terminal=true here, but kitty won't
        # show if that's the case. The tmux::attach func gets called though...
        terminal = false;
        exec = "${pkgs.kitty}/bin/kitty --class kitty-tmux -e ${tmuxAttach}";
        icon = pkgs.fetchurl {
          url = "https://raw.githubusercontent.com/tmux/tmux/master/logo/tmux-logomark.svg";
          sha256 = "0n73x1nhds5k4825x91409knjvkc7ps7cjrhknjg8g1w37r5djdx";
        };
      };

      "tmux-local-fnuc" = {
        name = "tmux@local+fnuc";
        comment = "Start kitty with local and fnuc tmux tabs";
        terminal = false;
        exec = "${pkgs.kitty}/bin/kitty --class kitty-tmux --session ${kittyTmuxSession}";
        icon = pkgs.fetchurl {
          url = "https://raw.githubusercontent.com/tmux/tmux/master/logo/tmux-logomark.svg";
          sha256 = "0n73x1nhds5k4825x91409knjvkc7ps7cjrhknjg8g1w37r5djdx";
        };
      };

      "tmux-fnuc" = {
        name = "tmux@fnuc";
        comment = "Start kitty with remote tmux on fnuc";
        terminal = false;
        exec = "${pkgs.kitty}/bin/kitty --class kitty-tmux -e ${remoteTmuxFnuc}";
        icon = pkgs.fetchurl {
          url = "https://raw.githubusercontent.com/tmux/tmux/master/logo/tmux-logomark.svg";
          sha256 = "0n73x1nhds5k4825x91409knjvkc7ps7cjrhknjg8g1w37r5djdx";
        };
      };
    };

    autostart = {
      enable = true;
      readOnly = true;

      entries = [
        "${config.home.profileDirectory}/share/applications/tmux-local-fnuc.desktop"
        "${pkgs.firefox}/share/applications/firefox.desktop"
        "${pkgs.nextcloud-client}/share/applications/com.nextcloud.desktopclient.nextcloud.desktop"
      ]
      ++ lib.optionals (hostname == "ge2") [
        "${config.home.profileDirectory}/share/applications/obs-studio-custom.desktop"
      ];
    };
  };
}
