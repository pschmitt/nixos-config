{ config, pkgs, ... }:
{
  sops.secrets."todoist/api_token" = { };

  home.sessionVariables = {
    TODOIST_API_TOKEN = "$(${pkgs.coreutils}/bin/cat ${config.sops.secrets."todoist/api_token".path})";
  };
}
