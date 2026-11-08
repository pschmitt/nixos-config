{ config, ... }:
let
  cfg = config.services.teams-live;
  secrets = config.sops.secrets;

  # Readable by the service and restarting it when the value changes.
  serviceSecret =
    extra:
    {
      owner = cfg.user;
      inherit (cfg) group;
      mode = "0400";
      restartUnits = [ "teams-live.service" ];
    }
    // extra;
  hostSecret = config.sops.mkHostSecret (serviceSecret { });

  # A value teams-live reads from the secret file at startup (docs/nix.md).
  secretValue = name: { _secret = secrets.${name}.path; };
in
{
  sops.secrets = {
    "teams-live/credentials" = hostSecret;
    "teams-live/gitlab-token" = hostSecret;
    "teams-live/gitlab-url" = hostSecret;
    "teams-live/gitlab-group" = hostSecret;
    "teams-live/conversation-notes" = hostSecret;
    "teams-live/conversation-team" = hostSecret;
    "teams-live/jira-url" = hostSecret;
    "teams-live/jira-token" = hostSecret;
    "teams-live/jira-board-id" = hostSecret;
    "teams-live/troll-user" = hostSecret;
    "opsgenie/gksv3-on-call/api-key" = hostSecret;
    "opsgenie/gksv3-support-schedule/api-key" = hostSecret;
    "opsgenie/edge-stack/api-key" = hostSecret;
    "browser-daemon/cluster-secret" = serviceSecret { };
    "home-assistant/token" = serviceSecret { sopsFile = config.sops.defaultSopsFile; };
  };

  services.teams-live = {
    enable = true;
    settings = {
      teams = {
        credentials_file = secrets."teams-live/credentials".path;
        troll_user = secretValue "teams-live/troll-user";
      };

      browser_daemon = {
        url = "https://browser.fnuc.nb.brkn.lol";
        profile = "ha-msteams";
        secret_file = secrets."browser-daemon/cluster-secret".path;
      };

      gitlab = {
        host = secretValue "teams-live/gitlab-url";
        group = secretValue "teams-live/gitlab-group";
        token_file = secrets."teams-live/gitlab-token".path;
        history_max_age_minutes = 15;
      };

      jira = {
        url = secretValue "teams-live/jira-url";
        token_file = secrets."teams-live/jira-token".path;
        board_id = secretValue "teams-live/jira-board-id";
      };

      opsgenie = {
        on_call_key = secretValue "opsgenie/gksv3-on-call/api-key";
        support_key = secretValue "opsgenie/gksv3-support-schedule/api-key";
        edge_key = secretValue "opsgenie/edge-stack/api-key";
      };

      home_assistant = {
        # Straight over NetBird: the public vhost times out slow service calls
        # (HR WORKS) after 60s and retries them through Nabu Casa.
        url = "http://ha.${config.domains.netbird}:8123";
        token_file = secrets."home-assistant/token".path;
      };

      conversations = [
        {
          id = secretValue "teams-live/conversation-notes";
          name = "Notes (Self)";
          gitlab = true;
        }
        {
          id = secretValue "teams-live/conversation-team";
          name = "Team";
          gitlab = true;
        }
      ];
    };
  };

  services.monit.checks.teams-live = {
    type = "program";
    path = cfg.healthCheck;
    group = [
      "services"
      "teams"
    ];
    restartUnit = "teams-live.service";
    conditions = ''
      if status > 0 for 2 cycles then restart
      if 3 restarts within 10 cycles then alert
    '';
  };
}
