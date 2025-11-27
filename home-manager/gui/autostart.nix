{
  config,
  lib,
  osConfig,
  pkgs,
  ...
}:
{
  home.packages = with pkgs; [
    nextcloud-client
  ];

  xdg = {
    desktopEntries = {
      tmux = {
        name = "tmux";
        comment = "Start main tmux session";
        # FIXME We *should* be able to use terminal=true here, but kitty won't
        # show if that's the case. The tmux::attach func gets called though...
        terminal = false;
        exec = "${pkgs.kitty}/bin/kitty --class kitty-tmux -e ${config.home.homeDirectory}/bin/zhj tmux::attach";
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
        "${config.home.profileDirectory}/share/applications/tmux.desktop"
        "${pkgs.firefox}/share/applications/firefox.desktop"
        "${pkgs.nextcloud-client}/share/applications/com.nextcloud.desktopclient.nextcloud.desktop"
      ]
      ++ lib.optionals (osConfig.networking.hostName == "ge2") [
        "${config.home.profileDirectory}/share/applications/obs-studio-custom.desktop"
      ];
    };
  };
}
