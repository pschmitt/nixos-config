# A persistent circus-agent (build agent for Circus CI, ./default.nix). It
# builds through this host's Nix daemon, next to nixbot's builds on the shared
# build nodes, so it takes few slots and the queue-runner skips it under
# pressure (psi_threshold).
{
  config,
  inputs,
  lib,
  ...
}:
let
  cfg = config.services.circus.agent;
in
{
  imports = [ inputs.circus.nixosModules.circus-agent ];

  options.services.circus.agent = {
    runnerHost = lib.mkOption {
      type = lib.types.str;
      example = "rofl-15";
      description = "Host running the Circus queue-runner, reached over NetBird or Tailscale.";
    };

    maxJobs = lib.mkOption {
      type = lib.types.ints.positive;
      default = 4;
      description = "Concurrent Circus builds on this host.";
    };

    cores = lib.mkOption {
      type = lib.types.ints.unsigned;
      default = 4;
      description = "Nix `cores` per Circus build (0: the host default).";
    };
  };

  config = {
    # Same value as on the other agents; the queue-runner holds its hash.
    sops.secrets."circus/agent-join-token" = config.sops.mkHostSecret { };

    services.circus-agent = {
      enable = true;
      joinTokenFile = config.sops.secrets."circus/agent-join-token".path;
      settings.agent = {
        name = config.networking.hostName;
        # TLS with the queue-runner host's tailnet ACME certificate.
        runner_url = "circus+tls://circus.${cfg.runnerHost}.${config.domains.vpn}:8443";
        systems = [ "x86_64-linux" ];
        supported_features = [
          "nixos-test"
          "benchmark"
          "big-parallel"
        ];
        max_jobs = cfg.maxJobs;
        inherit (cfg) cores;
      };
    };

    # The agent process only: builds run in the Nix daemon's cgroup.
    systemd.services.circus-agent.serviceConfig.MemoryMax = "2G";
  };
}
