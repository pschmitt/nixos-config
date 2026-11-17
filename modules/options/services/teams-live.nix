{ lib, ... }:
{
  options.services.teams-live.webhookHostNames = lib.mkOption {
    type = lib.types.listOf lib.types.str;
    default = [ ];
    description = ''
      Extra public names that serve only the GitLab webhook and the health
      check of teams-live, without Authelia: the webhook authenticates by its
      shared secret, and nothing but the webhook, the health check and, when
      enabled, the approval page is exposed on these names. The first
      one is the URL registered with GitLab; without any, it is the
      Authelia-protected default name.
    '';
  };

  options.services.teams-live.approval = {
    enable = lib.mkEnableOption ''
      the merge request approval page on the webhook host names. The page is
      public and protected only by an unguessable link token, so
      nginx neither logs requests to it nor its errors
    '';

    port = lib.mkOption {
      type = lib.types.port;
      default = 3006;
      description = "Loopback port of the approval listener, separate from the webhook listener.";
    };

    linkTtlSeconds = lib.mkOption {
      type = lib.types.ints.positive;
      default = 86400;
      description = "How long an approval link in a card stays valid.";
    };
  };
}
