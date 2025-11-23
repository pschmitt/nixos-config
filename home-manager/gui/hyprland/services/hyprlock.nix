{ config, pkgs, ... }:
let
  hyprlockWidgetsWrapper = pkgs.writeShellApplication {
    name = "hyprlock-widgets";
    runtimeInputs = with pkgs; [
      bash
      jc
      jq
      upower
    ];
    text = ''
      exec ${config.home.homeDirectory}/.config/hypr/bin/hyprlock-widgets.sh "$@"
    '';
  };
  hyprlockWidgetsScript = "${hyprlockWidgetsWrapper}/bin/hyprlock-widgets";
  profileImage = "${config.home.homeDirectory}/.face";

  font = "ComicCode Nerd Font";
in
{
  home.packages = [
    pkgs.chayang
  ];

  programs.hyprlock = {
    enable = true;
    settings = {
      general = {
        hide_cursor = true;
      };
      auth.fingerprint = {
        enabled = true;
        ready_message = "Waiting for fingerprint…";
        present_message = "Recognizing…";
      };
      background = [
        {
          monitor = "";
          path = "screenshot";
          blur_passes = 3;
          blur_size = 5;
          color = "rgba(25, 20, 20, 1.0)";
        }
      ];
      shape = [
        {
          monitor = "";
          size = "33%, 20%";
          color = "rgba(15, 15, 15, 0.9)";
          rounding = 25;
          border_size = 0;
          position = "0, -1%";
          halign = "center";
          valign = "center";
          zindex = -1;
        }
      ];
      image = [
        {
          monitor = "";
          path = profileImage;
          size = 200;
          rounding = -1;
          border_size = 4;
          border_color = "rgb(221, 221, 221)";
          position = "0, 18%";
          halign = "center";
          valign = "center";
        }
      ];
      label = [
        {
          monitor = "";
          text = "cmd[update:1000] date '+%Y-%m-%d %H:%M:%S'";
          color = "rgba(50, 50, 50, 1.0)";
          font_size = 40;
          font_family = font;
          position = "0, 4%";
          halign = "center";
          valign = "center";
        }
        {
          monitor = "";
          text = "Login attempts: $ATTEMPTS $FPRINTFAIL";
          color = "rgba(50, 50, 50, 1.0)";
          font_size = 30;
          font_family = font;
          position = "0, -7%";
          halign = "center";
          valign = "center";
        }
        {
          monitor = "";
          text = "cmd[update:1000] ${hyprlockWidgetsScript} battery";
          color = "rgba(200, 200, 200, 1.0)";
          font_size = 26;
          font_family = font;
          position = "-2%, 0";
          halign = "right";
          valign = "bottom";
        }
      ];
      "input-field" = [
        {
          monitor = "";
          size = "25%, 4%";
          outline_thickness = 3;
          dots_center = true;
          dots_size = 0.33;
          dots_spacing = 0.15;
          outer_color = "rgb(151515)";
          inner_color = "rgba(210, 210, 210, 0.65)";
          font_family = font;
          font_color = "rgb(10, 10, 10)";
          fade_on_empty = true;
          placeholder_text = "<i>Input Password...</i>";
          hide_input = false;
          position = "0, -2%";
          halign = "center";
          valign = "center";
        }
      ];
    };
  };
}
