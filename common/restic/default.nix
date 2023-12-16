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
    # identityPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
  };

  environment.systemPackages = [ pkgs.restic ];

  services.restic.backups = {
    "main" = {
      environmentFile = config.age.secrets.restic-env.path;
      passwordFile = config.age.secrets.restic-password.path;
      repositoryFile = config.age.secrets.restic-repository.path;

      paths = [
        "/etc/nixos"
        "${config.custom.homeDirectory}/devel"
        "${config.custom.homeDirectory}/Documents"
        "${config.custom.homeDirectory}/Pictures"
        "${config.custom.homeDirectory}/.config/obs-studio"
      ];
      timerConfig = {
        OnCalendar = "12:30:00";
        Persistent = true;
      };
      pruneOpts = [
        "--keep-last 5"
        "--keep-within 14d"
        "--keep-daily 1"
        "--keep-weekly 1"
        "--keep-monthly 1"
        "--keep-yearly 10"
        "--keep-tag do-not-delete"
        "--keep-tag keep-forever"
        "--keep-tag forever"
      ];
      initialize = false;
      createWrapper = true;
      exclude = [ ];
    };
  };
}
