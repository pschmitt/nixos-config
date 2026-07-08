{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib) mapAttrsToList concatStringsSep;

  cfg = config.services.ktunnel-xmrig-proxy;
  instances = lib.filterAttrs (_: inst: inst.enable) cfg;

  ktunnelHealthcheck = import ../xmr/ktunnel-healthcheck.nix { inherit pkgs; };

  monitInstance = name: inst: ''
    check program "ktunnel ${name}" with path "${
      ktunnelHealthcheck.mkCheckScript name inst ktunnelHealthcheck.staleAfterMs
    }"
      group "network"
      group "ktunnel"
      restart program = "${pkgs.systemd}/bin/systemctl restart ktunnel-xmrig-proxy-${name}.service"
      # NOTE: program checks run async -- monit evaluates the *previous*
      # run's exit code each cycle. With a bare "then restart" a single
      # transient failure restarts the service, the next run executes
      # while it's still coming up, fails and restarts it again -- forever.
      if status != 0 for 2 cycles then restart
      # recovery
      else if succeeded then exec "${pkgs.coreutils}/bin/true"
      if 5 restarts within 10 cycles then alert
  '';

  monitKtunnel = concatStringsSep "\n" (mapAttrsToList monitInstance instances);
in
{
  services.monit.config = lib.mkAfter monitKtunnel;

  systemd.services.monit.after = mapAttrsToList (
    name: _: "ktunnel-xmrig-proxy-${name}.service"
  ) instances;
}
