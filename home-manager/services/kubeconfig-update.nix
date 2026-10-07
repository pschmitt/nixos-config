{ lib, pkgs, ... }:
{
  systemd.user = {
    services.kubeconfig-update = {
      Unit.Description = "Update kubeconfigs";
      Service = {
        Type = "oneshot";
        ExecStartPre = "${lib.getExe pkgs.zhj} rancher::login-cli-all";
        ExecStart = "${lib.getExe pkgs.zhj} kubectl::kubeconfig-export-rancher";
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
