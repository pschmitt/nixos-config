{ pkgs, inputs, config, ... }:
let
  container_image = "ghcr.io/pschmitt/jcalapi";
  container_tag = "latest";
  container_name = "jcalapi";
  config_file = "${config.custom.homeDirectory}/devel/private/calendar-events/jcalapi/.envrc-secrets";
in
{
  environment.systemPackages = with pkgs; [
    podman
  ];

  systemd.user.services.jcalapi = {
    enable = true;
    description = "Local JSON API for calendar events";
    documentation = [ "https://github.com/pschmitt/jcalapi" ];
    after = [ "NetworkManager-wait-online.service" ];
    path = with pkgs; [
      "/run/wrappers"  # required for newuidmap
      podman
      systemd
    ];
    serviceConfig = {
      ExecStartPre = [
        "${pkgs.podman}/bin/podman pull ${container_image}:${container_tag}"
        "-${pkgs.podman}/bin/podman kill ${container_name}"
        "-${pkgs.podman}/bin/podman rm --force ${container_name}"
      ];
      ExecStart = "${pkgs.podman}/bin/podman run --tty --rm \\
        --name ${container_name} \\
        --net=host \\
        --env TZ='Europe/Berlin' \\
        --env-file ${config_file} \\
        ${container_image}:${container_tag}";
      ExecStartPost = "-${config.custom.homeDirectory}/bin/zhj 'sleep 10 && jcal reload'";
      ExecStop = "${pkgs.podman}/bin/podman stop ${container_name}";
      Restart = "always";
      RestartSec = "30";
      TimeoutStartSec = "0";
    };
    wantedBy = [ "default.target" ];
  };

}
