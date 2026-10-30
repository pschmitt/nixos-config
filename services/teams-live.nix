{
  config,
  ...
}:
let
  cfg = config.services.teams-live;
in
{
  sops.secrets = {
    "teams-live/gitlab-token" = config.sops.mkHostSecret {
      inherit (cfg) group;
      owner = cfg.user;
      mode = "0400";
      restartUnits = [ "teams-live.service" ];
    };

    "teams-live/credentials" = config.sops.mkHostSecret {
      inherit (cfg) group;
      owner = cfg.user;
      mode = "0400";
      restartUnits = [ "teams-live.service" ];
    };

    "teams-live/gitlab-url" = config.sops.mkHostSecret {
      inherit (cfg) group;
      owner = cfg.user;
      mode = "0400";
      restartUnits = [ "teams-live.service" ];
    };

    "teams-live/conversation-notes" = config.sops.mkHostSecret {
      inherit (cfg) group;
      owner = cfg.user;
      mode = "0400";
      restartUnits = [ "teams-live.service" ];
    };

    "teams-live/conversation-team" = config.sops.mkHostSecret {
      inherit (cfg) group;
      owner = cfg.user;
      mode = "0400";
      restartUnits = [ "teams-live.service" ];
    };
  };

  sops.templates."teams-live/config.json" = {
    owner = cfg.user;
    inherit (cfg) group;
    mode = "0400";
    content = builtins.toJSON {
      gitlab = {
        host = config.sops.placeholder."teams-live/gitlab-url";
        token_file = config.sops.secrets."teams-live/gitlab-token".path;
        poll_interval_seconds = 60;
        history_limit = 50;
        history_max_age_minutes = 10;
        max_watch_duration_seconds = 7200;
        notify = {
          ci = {
            enable = true;
            on_failure = true;
            on_success = true;
          };
          rebase = true;
          approval_lost = true;
        };
      };

      teams = {
        credentials_file = config.sops.secrets."teams-live/credentials".path;
        reconnect_interval_seconds = 5;
        token_refresh_interval_minutes = 60;
      };

      conversations = [
        {
          id = config.sops.placeholder."teams-live/conversation-notes";
          name = "Notes (Self)";
          gitlab = true;
        }
        {
          id = config.sops.placeholder."teams-live/conversation-team";
          name = "Team";
          gitlab = true;
        }
      ];
    };
  };

  services.teams-live = {
    enable = true;
    configFile = config.sops.templates."teams-live/config.json".path;
  };
}
