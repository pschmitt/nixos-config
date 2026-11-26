{ inputs, pkgs, ... }:
{
  home.packages = [ pkgs.jq ];
  # force: replaces the links the old zinit jq.zsh created.
  xdg.configFile = {
    "jq/colors" = {
      source = inputs.colors-jq;
      force = true;
    };
    "jq/plib" = {
      source = inputs.plib-jq;
      force = true;
    };
  };
}
