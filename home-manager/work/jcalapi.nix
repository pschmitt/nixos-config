{
  config,
  inputs,
  ...
}:
{
  imports = [
    inputs.jcalapi.homeManagerModules.default
  ];

  sops.secrets = {
    "jcalapi/env" = {
      mode = "0600";
    };
    "jcalapi/googleCredentials" = {
      mode = "0600";
    };
  };

  services.jcalapi = {
    enable = true;
    google.credentialsFile = config.sops.secrets."jcalapi/googleCredentials".path;
    port = 7042;
    extraEnvFile = config.sops.secrets."jcalapi/env".path;
    reloadHook = {
      enable = true;
      delaySeconds = 10;
    };
    wantedBy = [ "graphical-session.target" ];
  };
}
