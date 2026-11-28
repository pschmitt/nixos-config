# alles (alles.brkn.lol): the server behind the alles Android app, via the
# upstream NixOS module (nix/module.nix of the `alles` flake input).
#
# Connectors are named credential sets; the users file (SOPS) maps each
# Authelia user to the sets they use and holds their names and person
# entities, so neither lands in this repository or the Nix store.
{
  config,
  inputs,
  ...
}:
let
  host = "alles.${config.domains.main}";
  secret = name: config.sops.secrets.${name}.path;
  owned = {
    owner = "alles";
    group = "alles";
  };
in
{
  imports = [ inputs.alles.nixosModules.default ];

  sops.secrets = {
    "alles/oidc/clientSecret" = config.sops.mkHostSecret owned;
    "alles/serviceToken" = config.sops.mkHostSecret owned;
    "alles/users" = config.sops.mkHostSecret (owned // { restartUnits = [ "alles.service" ]; });
    # Same value as Hermes's API server key (services/hermes.nix).
    "alles/hermesApiKey" = config.sops.mkHostSecret (owned // { key = "hermes/apiServer/key"; });
    # The restricted `anika` Hermes profile's key (services/hermes.nix).
    "alles/hermesAnikaKey" = config.sops.mkHostSecret (owned // { key = "hermes/apiServer/anikaKey"; });
    # Shared Home Assistant and Todoist tokens (default SOPS file).
    "alles/homeAssistantToken" = owned // {
      key = "home-assistant/token";
    };
    "alles/todoistToken" = owned // {
      key = "todoist/api_token";
    };
  };

  services.alles = {
    enable = true;
    nginx = {
      enable = true;
      hostName = host;
    };
    settings = {
      public_url = "https://${host}";
      timezone = "Europe/Berlin";
      users_file = secret "alles/users";

      oidc = {
        issuer = "https://auth.${config.domains.main}";
        client_id = "alles";
        client_secret_file = secret "alles/oidc/clientSecret";
      };

      home_assistant.home = {
        url = "https://ha.${config.domains.main}";
        token_file = secret "alles/homeAssistantToken";
      };
      todoist.main.token_file = secret "alles/todoistToken";
      # The main Hermes (every tool), and the restricted `anika` profile
      # (services/hermes.nix). The users file maps each user to one.
      hermes = {
        hermes = {
          base_url = "http://127.0.0.1:8642/v1";
          api_key_file = secret "alles/hermesApiKey";
          model = "hermes-agent";
          briefing = true;
        };
        anika = {
          base_url = "http://127.0.0.1:8642/p/anika/v1";
          api_key_file = secret "alles/hermesAnikaKey";
          model = "hermes-agent";
          briefing = true;
        };
      };

      push = {
        subject = "https://github.com/pschmitt/alles";
        # UnifiedPush distributors and browser Web Push services.
        allowed_hosts = [
          "ntfy.sh"
          "fcm.googleapis.com"
          "push.services.mozilla.com"
          "push.apple.com"
        ];
        service_token_file = secret "alles/serviceToken";
      };

      shortcuts = [
        {
          id = "bedtime";
          title = "Bedtime";
          subtitle = "Bedroom lights down";
          icon = "moon";
          color = "coral";
          pinned = true;
          action = {
            kind = "script";
            entity_id = "script.bedtime";
          };
        }
        {
          id = "all-off";
          title = "All off";
          icon = "bolt";
          color = "sun";
          pinned = true;
          action = {
            kind = "script";
            entity_id = "script.all_off";
          };
        }
        {
          id = "feierabend";
          title = "Feierabend";
          icon = "coffee";
          color = "sky";
          pinned = true;
          action = {
            kind = "script";
            entity_id = "script.feierabend";
          };
        }
        {
          id = "living-room";
          title = "Living room";
          icon = "bulb";
          color = "surface";
          action = {
            kind = "toggle";
            entity_id = "light.hue_living_room_light";
          };
        }
        {
          id = "couch";
          title = "Couch";
          icon = "bulb";
          color = "surface";
          action = {
            kind = "toggle";
            entity_id = "light.hue_couch_light";
          };
        }
        {
          id = "kitchen";
          title = "Kitchen";
          icon = "bulb";
          color = "surface";
          action = {
            kind = "toggle";
            entity_id = "light.ikea_kitchen_ceiling_light";
          };
        }
        {
          id = "buzz-open";
          title = "Buzz open";
          subtitle = "Front door buzzer";
          icon = "lock";
          color = "surface";
          action = {
            kind = "script";
            entity_id = "script.buzz_open";
          };
        }
      ];
    };
  };

  services.nginx.virtualHosts.${host} = {
    enableACME = false;
    useACMEHost = "wildcard.${config.domains.main}";
  };
}
