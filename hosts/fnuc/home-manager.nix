{ config, ... }:
{
  home-manager.users.${config.mainUser.username} = {
    imports = [
      ../../modules/home-manager/claude-remote-control.nix
      ../../modules/home-manager/codex-remote-control.nix

      ../../services/claude-work-warmup.nix
      ../../services/agy-warmup.nix
      ../../services/terminal-browser-headless.nix
      ./immich-mcp.nix
    ];

    services.codex-remote-control.enable = true;
    services.terminal-browser-headless.enable = true;
  };
}
