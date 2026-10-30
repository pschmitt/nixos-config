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
  };

  services.teams-live = {
    enable = true;
    credentialsFile = config.sops.secrets."teams-live/credentials".path;
    gitlabTokenFile = config.sops.secrets."teams-live/gitlab-token".path;

    settings = {
      gitlab = {
        host = "git.wiit.one";
        poll_interval_seconds = 60;
        history_limit = 50;
        notify_ci = true;
        notify_ci_on_failure = true;
        notify_ci_on_success = true;
        notify_rebase = true;
        notify_approval_lost = true;
      };

      teams = {
        reconnect_interval_seconds = 5;
        token_refresh_interval_minutes = 60;
      };

      conversations = [
        # Testing phase: watch chat with self (Notes)
        {
          id = "48:notes";
          name = "Notes (Self)";
          gitlab = true;
        }
        # K-Team group chat: enable later when ready
        # {
        #   id = "19:meeting_MDgyMjE4NzctNjkzNi00ZDBkLThiNjEtOTU2ZTBkZTNlM2Vl@thread.v2";
        #   name = "K-Team";
        #   gitlab = true;
        # }
      ];
    };
  };
}
