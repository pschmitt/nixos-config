{
  config,
  osConfig,
  pkgs,
  ...
}:

let
  containerName = "jcalapi";
  image = "ghcr.io/pschmitt/jcalapi:latest";
  port = 7042;
  dataDir = "${config.xdg.dataHome}/${containerName}";
  envFile = config.sops.secrets."jcalapi/env".path;
  userCfg = osConfig.users.users.${config.home.username} or { };
  userId = userCfg.uid or 1000;
  groupId =
    let
      groupName = userCfg.group or config.home.username;
    in
    osConfig.users.groups.${groupName}.gid or userId;
in

{
  sops.secrets = {
    "jcalapi/env" = {
      mode = "0600";
    };
    "jcalapi/googleCredentials" = {
      mode = "0600";
      path = "${dataDir}/google-credentials.json";
    };
  };

  services.podman = {
    enable = true;

    containers.${containerName} = {
      inherit image;
      autoStart = true;
      user = "${toString userId}";
      group = "${toString groupId}";
      environment = {
        TZ = "Europe/Berlin";
        GOOGLE_CREDENTIALS = "/data/google-credentials.json";
      };
      environmentFile = [ envFile ];
      ports = [ "127.0.0.1:${toString port}:${toString port}" ];
      volumes = [
        "${dataDir}:/data:Z"
      ];
      extraConfig = {
        Unit = {
          After = [ "sops-nix.service" ];
          Wants = [ "sops-nix.service" ];
        };
        Service = {
          ExecStartPost = [
            "${pkgs.coreutils}/bin/sleep 10"
            "${pkgs.curl}/bin/curl -X POST http://127.0.0.1:${toString port}/reload"
          ];
        };
      };
    };
  };

  systemd.user.tmpfiles.rules = [
    "d ${dataDir} 0700 ${config.home.username} ${config.home.username}"
  ];
}
