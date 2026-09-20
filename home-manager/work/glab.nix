{ config, ... }:
{
  custom.glab.work.enable = true;

  sops.secrets."glab/git.wiit.one/token" = {
    sopsFile = config.host.sopsDefaultFile;
  };
}
