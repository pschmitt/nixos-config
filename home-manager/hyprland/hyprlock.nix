{ config, ... }:
let
  hyprBinDir = "${config.home.homeDirectory}/.config/hypr/bin";
  hyprlockWidgetsScript = "${hyprBinDir}/hyprlock-widgets.sh";
  profileImage = "${config.home.homeDirectory}/.face";
in
{
  programs.hyprlock = {
    enable = true;
    settings = {
      general = {
        disable_loading_bar = false;
        hide_cursor = true;
        no_fade_in = false;
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
      image = [
        {
          monitor = "";
          path = profileImage;
          size = 125;
          rounding = -1;
          border_size = 4;
          border_color = "rgb(221, 221, 221)";
          position = "0, 200";
          halign = "center";
          valign = "center";
        }
      ];
      label = [
        {
          monitor = "";
          text = "cmd[update:1000] date '+%Y-%m-%d %H:%M:%S'";
          color = "rgba(50, 50, 50, 1.0)";
          font_size = 25;
          font_family = "Comic Code";
          position = "0, 40";
          halign = "center";
          valign = "center";
        }
        {
          monitor = "";
          text = "Login attempts: $ATTEMPTS $FPRINTFAIL";
          color = "rgba(50, 50, 50, 1.0)";
          font_size = 20;
          font_family = "Comic Code";
          position = "0, -75";
          halign = "center";
          valign = "center";
        }
        {
          monitor = "";
          text = "cmd[update:1000] ${hyprlockWidgetsScript} battery";
          color = "rgba(200, 200, 200, 1.0)";
          font_size = 18;
          font_family = "Comic Code";
          position = "-20, 0";
          halign = "right";
          valign = "bottom";
        }
      ];
      "input-field" = [
        {
          monitor = "";
          size = "300, 50";
          outline_thickness = 3;
          dots_center = true;
          dots_size = 0.33;
          dots_spacing = 0.15;
          outer_color = "rgb(151515)";
          inner_color = "rgb(200, 200, 200)";
          font_color = "rgb(10, 10, 10)";
          fade_on_empty = true;
          placeholder_text = "<i>Input Password...</i>";
          hide_input = false;
          position = "0, -20";
          halign = "center";
          valign = "center";
        }
      ];
    };
  };
}
