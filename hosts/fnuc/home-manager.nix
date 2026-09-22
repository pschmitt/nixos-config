{ config, ... }:
{
  home-manager.users.${config.mainUser.username} =
    { config, ... }:
    {
      imports = [
        ../../modules/home-manager/claude-remote-control.nix
        ../../modules/home-manager/codex-remote-control.nix
        ../../services/nix-distributed-build.nix

        ../../services/claude-work-warmup.nix
        ../../services/agy-warmup.nix
      ];

      nix.settings.max-jobs = 0;

      sops.secrets."ssh/nix-remote-builder/privkey".mode = "0400";
    };
}
