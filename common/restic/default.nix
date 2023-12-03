{ config, pkgs, ... }:
let
  hostname = config.networking.hostName;
in
{
  age = {
    secrets = {
      restic-repository.file = ../../secrets/${hostname}/restic-repository.age;
      restic-password.file = ../../secrets/${hostname}/restic-password.age;
      restic-env.file = ../../secrets/${hostname}/restic-env.age;
    };
    identityPaths = [ "${config.custom.sshKey}" ];
  };

  services.restic.backups = {
    "main" = {
      environmentFile = config.age.secrets.restic-env.path;
      passwordFile = config.age.secrets.restic-password.path;
      repositoryFile = config.age.secrets.restic-repository.path;

      paths = [
        "${config.custom.homeDirectory}/devel"
        "${config.custom.homeDirectory}/Documents"
        "${config.custom.homeDirectory}/Pictures"
      ];
      timerConfig = {
        OnCalendar = "12:30:00";
        Persistent = true;
      };
      pruneOpts = [
        "--keep-last 5"
        "--keep-within 2w"
        "--keep-daily 1"
        "--keep-weekly 1"
        "--keep-monthly 1"
        "--keep-yearly 10"
      ];
      initialize = false;
      createWrapper = true;
      exclude = [ ];
    };
  };
}
