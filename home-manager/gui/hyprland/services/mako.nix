{
  pkgs,
  config,
  lib,
  ...
}:
{
  home.packages = [
    pkgs.libnotify # notify-send
  ];

  services.mako = {
    enable = true;
    settings =
      let
        fontName = "ComicCode Nerd Font";
        infoBanner = {
          font = "${fontName} 24";
          anchor = "center";
          "text-color" = "#e8e9ea";
          "text-alignment" = "center";
          "background-color" = "#323232AF";
          "progress-color" = "over #262626AF";
          "border-size" = 0;
          "border-radius" = 5;
          "default-timeout" = 1000;
          history = 0;
        };
        osdCategory = infoBanner;
      in
      {
        font = "${fontName} 14";
        layer = "overlay";
        history = 1;
        icons = true;
        icon-path = lib.concatStringsSep ":" (
          lib.filter (p: p != null) [
            "${config.gtk.iconTheme.package}/share/icons/${config.gtk.iconTheme.name}"
            "${pkgs.adwaita-icon-theme}/share/icons/Adwaita"
            "${pkgs.hicolor-icon-theme}/share/icons/hicolor"

            "/run/current-system/sw/share/icons/Adwaita"
            "/run/current-system/sw/share/icons/hicolor"

            "${config.home.profileDirectory}/share/pixmaps"
            "/run/current-system/sw/share/pixmaps"
          ]
        );

        actions = true;
        "default-timeout" = 10000;
        width = 400;
        "border-radius" = 5;
        markup = true;

        # Optional future overrides from ~/.config/mako/config:
        #   icon-path = /home/pschmitt/Pictures/Icons

        "mode=do-not-disturb" = {
          invisible = true;
        };

        "urgency=low" = {
          "background-color" = "#2c2c2c";
          "border-color" = "#2c2c2c";
          "default-timeout" = 5000;
        };

        "urgency=normal" = {
          "background-color" = "#202020";
          "border-color" = "#202020";
          "default-timeout" = 10000;
        };

        "urgency=high" = {
          "background-color" = "#bf616a";
          "border-color" = "#bf616a";
          "default-timeout" = 0;
        };

        "category=osd-top-center" = infoBanner // {
          anchor = "top-center";
        };

        "category=osd-bottom-center" = infoBanner // {
          anchor = "bottom-center";
        };

        "category=osd" = osdCategory;

        "app-name=barify" = infoBanner;
        "app-name=barify summary~=Mute" = {
          "text-color" = "#e27978";
        };

        "app-name=poweralertd" = {
          "default-timeout" = 3000;
          anchor = "top-center";
        };

        "app-name=feierabend" = {
          font = "${fontName} 32";
          width = 800;
          height = 1024;
          anchor = "center";
          "text-color" = "#e8e9ea";
          "text-alignment" = "center";
          "background-color" = "#FF0000";
          "progress-color" = "over #262626AF";
          "border-size" = 0;
          "border-radius" = 5;
          "default-timeout" = 1000;
          history = 0;
        };

        "app-name=feierabend summary~=aborted" = {
          "text-color" = "#000000";
          "background-color" = "#77dd77";
        };

        "app-name=wofi-run" = {
          font = "${fontName} 18";
          width = 600;
          anchor = "top-center";
          "text-color" = "#2e4a62";
          "text-alignment" = "center";
          "background-color" = "#aec6cf";
          "border-size" = 0;
          "border-radius" = 20;
          "default-timeout" = 2000;
          history = 0;
        };

        "category=bluetooth" = {
          font = "${fontName} 18";
          "background-color" = "#365b81";
          "text-color" = "#aaaaaa";
          anchor = "top-center";
          "border-size" = 0;
          "border-radius" = 10;
          "text-alignment" = "center";
          width = 500;
        };

        "urgency=normal category=info" = {
          "border-color" = "#6EC9F5";
        };

        "urgency=normal category=success" = {
          "border-color" = "#A8D38D";
        };

        "urgency=normal category=warning" = {
          "border-color" = "#F3BD6A";
        };

        "urgency=normal category=error" = {
          "border-radius" = 10;
          "border-color" = "#bf616a";
          "background-color" = "#bf616a";
        };

        "urgency=normal category=failure" = {
          "border-radius" = 10;
          "border-color" = "#F1705F";
        };
      };
  };
}
