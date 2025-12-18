{
  inputs,
  lib,
  config,
  osConfig,
  ...
}:
{
  imports = [
    inputs.jellysync.homeManagerModules.default
  ];

  services.jellysync = {
    enable = lib.mkDefault false;

    settings = {
      remote = {
        hostname = "tv.${osConfig.domains.main}";
        inherit (config.home) username;
        port = 22;
        root = "/mnt/data/videos";
        directories = {
          tv_shows = "tv_shows";
          movies = "movies";
        };
      };

      local = {
        root = "${config.home.homeDirectory}/Videos";
        directories = {
          tv_shows = "TV Shows";
          movies = "Movies";
        };
      };

      jobs = {
        Fallout = {
          directory = "tv_shows";
          wildcard = true;
          seasons = "latest";
        };

        # Sync all of pluribus
        Pluribus = {
          directory = "tv_shows";
        };

        "The Paper" = {
          directory = "tv_shows";
          wildcard = true;
          seasons = "latest";
        };

        # Andor = {
        #   directory = "tv_shows";
        #   seasons = "latest";
        # };
      };
    };

    schedule = lib.mkForce "hourly";
    persistent = false;

    # Sync all jobs (empty list = all jobs)
    jobNames = [ ];
  };
}
