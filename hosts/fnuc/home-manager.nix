{ config, pkgs, ... }:
{
  imports = [ ../../profiles/specializations/server/interactive/browser.nix ];

  home-manager.users.${config.mainUser.username} = {
    imports = [
      ../../modules/home-manager/claude-remote-control.nix

      ../../services/agy-warmup.nix
      ../../services/terminal-browser-headless.nix
      ./immich-mcp.nix
    ];

    home.packages = [
      pkgs.desktui
      # kitten icat for fzf-preview images (the outer terminal is a remote kitty)
      pkgs.kitty
      pkgs.openstack-console-tui
    ];

    services.terminal-browser-headless.enable = true;
  };
}
