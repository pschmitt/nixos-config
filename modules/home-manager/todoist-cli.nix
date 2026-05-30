{
  config,
  ...
}:
{
  sops = {
    secrets = {
      "todoist/api_token" = {
        sopsFile = ../../secrets/shared.sops.yaml;
      };
      "todoist/user_id" = {
        sopsFile = ../../secrets/shared.sops.yaml;
      };
      "todoist/email" = {
        sopsFile = ../../secrets/shared.sops.yaml;
      };
    };

    templates."todoist-cli-config" = {
      path = "${config.xdg.configHome}/todoist-cli/config.json";
      mode = "0600";
      content = ''
        {
          "config_version": 2,
          "users": [
            {
              "id": "${config.sops.placeholder."todoist/user_id"}",
              "email": "${config.sops.placeholder."todoist/email"}",
              "auth_mode": "unknown",
              "api_token": "${config.sops.placeholder."todoist/api_token"}"
            }
          ],
          "user": {
            "defaultUser": "${config.sops.placeholder."todoist/user_id"}"
          }
        }
      '';
    };
  };
}
