{ config, pkgs, ... }:
{
  home-manager.users.${config.mainUser.username} = {
    imports = [
      ../../modules/home-manager/claude-remote-control.nix

      ../../services/claude-work-warmup.nix
      ../../services/agy-warmup.nix
      ../../services/terminal-browser-headless.nix
      ./immich-mcp.nix
    ];

    # kitten icat for fzf-preview images (the outer terminal is a remote kitty)
    home.packages = [ pkgs.kitty ];

    services.terminal-browser-headless.enable = true;
  };
}
