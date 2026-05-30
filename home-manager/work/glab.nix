{
  custom.glab.work.enable = true;

  sops.secrets."glab/git.wiit.one/token" = {
    sopsFile = ../../secrets/shared.sops.yaml;
  };
}
