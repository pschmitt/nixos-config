{ config, ... }:
{
  systemd.user = {
    services.kubeconfig-update = {
      Unit.Description = "Update kubeconfigs";
      Service = {
        Type = "oneshot";
        ExecStartPre = "${config.home.homeDirectory}/bin/zhj rancher::login-cli-all";
        ExecStart = "${config.home.homeDirectory}/bin/zhj kubectl::kubeconfig-export-rancher";
      };
    };

    timers.kubeconfig-update = {
      Unit.Description = "Periodically update kubeconfigs";
      Timer = {
        OnCalendar = "12:30:00";
        RandomizedDelaySec = "30m";
        Persistent = true;
      };
      Install.WantedBy = [ "timers.target" ];
    };
  };
}
