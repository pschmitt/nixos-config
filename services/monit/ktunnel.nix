{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib) mapAttrsToList concatStringsSep;

  xmrigInstances = lib.filterAttrs (_: inst: inst.enable) config.services.ktunnel-xmrig-proxy;
  inetProxyInstances = lib.filterAttrs (_: inst: inst.enable) config.services.inet-proxy.clusters;

  xmrigHealthcheck = import ../xmr/ktunnel-healthcheck.nix { inherit pkgs; };
  inetProxyHealthcheck = import ../ktunnel/inet-proxy-healthcheck.nix { inherit pkgs; };

  # NOTE: program checks run async -- monit evaluates the *previous* run's
  # exit code each cycle. With a bare "then restart" a single transient
  # failure restarts the service, the next run executes while it's still
  # coming up, fails and restarts it again -- forever.
  mkMonitCheck =
    {
      checkName,
      checkScript,
      restartUnit,
      extraGroups ? [ ],
    }:
    ''
      check program "ktunnel ${checkName}" with path "${checkScript}"
        group "network"
        group "ktunnel"
        ${concatStringsSep "\n  " (map (g: ''group "${g}"'') extraGroups)}
        restart program = "${pkgs.systemd}/bin/systemctl restart ${restartUnit}"
        if status != 0 for 2 cycles then restart
        # recovery
        else if succeeded then exec "${pkgs.coreutils}/bin/true"
        if 5 restarts within 10 cycles then alert
    '';

  # Unchanged from before this file gained inet-proxy coverage: same check
  # names ("ktunnel <cluster>") and groups, so any existing alert
  # routing/silencing keyed off them keeps working.
  xmrigChecks = mapAttrsToList (
    name: inst:
    mkMonitCheck {
      checkName = name;
      checkScript = xmrigHealthcheck.mkCheckScript name inst xmrigHealthcheck.staleAfterMs;
      restartUnit = "ktunnel-xmrig-proxy-${name}.service";
    }
  ) xmrigInstances;

  # Namespaced as "inet-proxy-<cluster>" rather than bare "<cluster>": rofl-12
  # runs both services.ktunnel-xmrig-proxy and services.inet-proxy against the
  # same cluster names (e.g. both have a "cluster-02"), so reusing the xmrig
  # naming scheme here would register two monit checks with the identical
  # name "ktunnel cluster-02".
  inetProxyChecks = mapAttrsToList (
    name: inst:
    mkMonitCheck {
      checkName = "inet-proxy-${name}";
      checkScript = inetProxyHealthcheck.mkCheckScript name {
        inherit (inst) kubeconfig namespace serviceName;
        port = config.services.inet-proxy.port;
        checkPort = inst.tunnelPort + 1;
      };
      restartUnit = "ktunnel-inet-proxy-${name}.service";
      extraGroups = [ "inet-proxy" ];
    }
  ) inetProxyInstances;

  monitKtunnel = concatStringsSep "\n" (xmrigChecks ++ inetProxyChecks);
in
{
  services.monit.config = lib.mkAfter monitKtunnel;

  systemd.services.monit.after =
    mapAttrsToList (name: _: "ktunnel-xmrig-proxy-${name}.service") xmrigInstances
    ++ mapAttrsToList (name: _: "ktunnel-inet-proxy-${name}.service") inetProxyInstances;
}
