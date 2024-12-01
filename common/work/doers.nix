{ config, ... }:
{
  sops = {
    secrets = {
      "artifactory/username" = { };
      "artifactory/password" = { };
      "gitlab/username" = { };
      "gitlab/password" = { };
    };

    templates.doers-envrc = {
      owner = config.custom.username;
      content = ''
        export VENDIR_SECRET_ARTIFACTORY_USERNAME=${config.sops.placeholder."artifactory/username"}
        export VENDIR_SECRET_ARTIFACTORY_PASSWORD=${config.sops.placeholder."artifactory/password"}
        export VENDIR_SECRET_GITLAB_USERNAME=${config.sops.placeholder."gitlab/username"}
        export VENDIR_SECRET_GITLAB_PASSWORD=${config.sops.placeholder."gitlab/password"}
      '';
    };
  };
}
