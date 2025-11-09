{ config, ... }:
{
  programs.starship = {
    enable = true;
    presets = [ "nerd-font-symbols" ];
    settings = {
      add_newline = false;
      # Single line prompt
      line_break.disabled = true;

      username = {
        style_root = "bold red";
        style_user = "bold green";
        format = "[$user]($style)";
      };
      hostname = {
        format = "@[$hostname]($style) ";
        ssh_only = false;
        style = "bold ${config.custom.promptColor}";
      };
      directory = {
        style = "bold green";
      };
      character = {
        success_symbol = "[»](bold green)";
        error_symbol = "[✗](bold red)";
      };
    };
  };
}
