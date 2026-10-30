{
  config,
  lib,
  ...
}:
let
  cfg = config.services.teams-live;
  mkSecret =
    extra:
    config.sops.mkHostSecret (
      {
        inherit (cfg) group;
        owner = cfg.user;
        mode = "0400";
        restartUnits = [ "teams-live.service" ];
      }
      // extra
    );
  mkSecrets = names: lib.genAttrs names (_name: mkSecret { });
in
{
  sops.secrets =
    (mkSecrets [
      "teams-live/credentials"
      "teams-live/gitlab-token"
      "teams-live/gitlab-url"
      "teams-live/gitlab-group"
      "teams-live/conversation-notes"
      "teams-live/conversation-team"
      "teams-live/jira-url"
      "teams-live/jira-token"
      "teams-live/jira-board-id"
      "teams-live/troll-user"
    ])
    // {
      "opsgenie/gksv3-on-call/api-key" = config.sops.mkHostSecret {
        restartUnits = [ "teams-live.service" ];
      };
      "opsgenie/gksv3-support-schedule/api-key" = config.sops.mkHostSecret {
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
        group = config.sops.placeholder."teams-live/gitlab-group";
        poll_interval_seconds = 60;
        history_limit = 50;
        history_max_age_minutes = 15;
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

      jira = {
        url = config.sops.placeholder."teams-live/jira-url";
        token_file = config.sops.secrets."teams-live/jira-token".path;
        board_id = config.sops.placeholder."teams-live/jira-board-id";
      };

      opsgenie = {
        on_call_key = config.sops.placeholder."opsgenie/gksv3-on-call/api-key";
        support_key = config.sops.placeholder."opsgenie/gksv3-support-schedule/api-key";
        on_call_schedule_id = "8aa71a67-9ddd-4571-af97-06d1ddb3c7cb";
        support_schedule_id = "5a044893-0255-4246-8606-8e76949a861d";
      };

      teams = {
        credentials_file = config.sops.secrets."teams-live/credentials".path;
        reconnect_interval_seconds = 5;
        token_refresh_interval_minutes = 60;
        troll_user = config.sops.placeholder."teams-live/troll-user";
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
