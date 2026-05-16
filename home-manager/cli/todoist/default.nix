{ config, ... }:
{
  sops = {
    secrets."todoist/api_token" = {
      sopsFile = ../../../secrets/shared.sops.yaml;
    };

    templates."todoist-cli-config" = {
      path = "${config.xdg.configHome}/todoist-cli/config.json";
      mode = "0600";
      content = ''
        {"api_token":"${config.sops.placeholder."todoist/api_token"}"}
      '';
    };
  };
}
