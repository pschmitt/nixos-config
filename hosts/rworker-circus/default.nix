# A pool rworker for Circus CI (services/circus): the standard build image
# plus a circus-agent that dials the queue-runner on the Circus host over
# NetBird. The rworker autoscaler on the ad-hoc control host creates these on
# Circus demand and hands each one the pool's agent join token through the
# OpenStack user-data (`circus_join_token`), never through the image. The
# same user-data carries the private S3 cache (`nix_cache_conf`,
# `nix_cache_aws_credentials`: read-only), because a circus-agent substitutes
# through this host's Nix daemon only; without it every dependency would be
# rebuilt here.
{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  joinDir = "/run/circus-join";
  # Where hosts/rworker/builder.nix includes cache settings from.
  cacheDir = "/run/rworker-nix";
  # The queue-runner's host (services.circus.agent.runnerHost elsewhere).
  runnerHost = "rofl-15";
in
{
  imports = [
    ../rworker
    inputs.circus.nixosModules.circus-agent
  ];

  # The metadata service hands out the user-data, including the reusable
  # join token, to anything on the VM that asks, fixed-output builds
  # included. Only root (the bootstrap units) may reach it.
  networking.firewall = {
    extraCommands = ''
      iptables -w -D OUTPUT -d 169.254.169.254 -m owner ! --uid-owner 0 -j REJECT 2>/dev/null || true
      iptables -w -A OUTPUT -d 169.254.169.254 -m owner ! --uid-owner 0 -j REJECT
    '';
    extraStopCommands = ''
      iptables -w -D OUTPUT -d 169.254.169.254 -m owner ! --uid-owner 0 -j REJECT 2>/dev/null || true
    '';
  };

  # Nothing pushes cache settings over SSH to a pool worker: circus-join
  # writes them at boot and restarts the daemon itself, before the agent.
  systemd.paths.rworker-nix-config.enable = false;

  systemd.services = {
    circus-join = {
      description = "Fetch the Circus agent join token from the user-data";
      wantedBy = [ "multi-user.target" ];
      after = [ "rworker-netbird-up.service" ];
      requires = [ "rworker-netbird-up.service" ];
      before = [ "circus-agent.service" ];
      path = [
        config.systemd.package
        pkgs.coreutils
        pkgs.curl
        pkgs.gnused
        pkgs.jq
      ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        StandardError = "journal+console";
      };
      script = ''
        metadata=$(sed -n 's/.*nixbot-worker\.metadata=\([^ ]*\).*/\1/p' /proc/cmdline)
        metadata="''${metadata:-http://169.254.169.254/openstack/latest}"
        install -d -m 0700 ${joinDir}
        umask 077
        user_data=$(mktemp -p ${joinDir})
        trap 'rm -f -- "$user_data"' EXIT
        curl -fsS --retry 30 --retry-delay 2 --retry-connrefused \
          "$metadata/user_data" > "$user_data"
        if ! jq -e '.circus_join_token | strings | length > 0' "$user_data" >/dev/null
        then
          echo "circus-join: no circus_join_token in the user-data" >&2
          exit 1
        fi
        jq -jr '.circus_join_token' "$user_data" > ${joinDir}/token

        # The private S3 cache, where ad-hoc workers get it from
        # `rworker nix-cache` (hosts/rworker/builder.nix): credentials first,
        # nix.conf last, then the daemon rereads its configuration before
        # the agent starts.
        if jq -e '(.nix_cache_conf | strings) and (.nix_cache_aws_credentials | strings)' "$user_data" >/dev/null
        then
          jq -jr '.nix_cache_aws_credentials + "\n"' "$user_data" > ${cacheDir}/aws-credentials
          jq -jr '.nix_cache_conf + "\n"' "$user_data" > ${cacheDir}/nix.conf
          systemctl restart nix-daemon.service
        else
          echo "circus-join: no private cache in the user-data, substituting from public caches only" >&2
        fi
        # The worker's OpenStack name, unique in the pool, as agent name.
        printf 'CIRCUS_AGENT__AGENT__NAME=%s\n' "$(hostname)" > ${joinDir}/env
      '';
    };

    circus-agent = {
      after = [ "circus-join.service" ];
      requires = [ "circus-join.service" ];
      serviceConfig = {
        EnvironmentFile = "${joinDir}/env";
        # The worker exists for Circus only: no slot budget to share.
        MemoryMax = lib.mkDefault "4G";
      };
    };
  };

  services.circus-agent = {
    enable = true;
    # Read by systemd (LoadCredential) when the agent starts.
    joinTokenFile = "${joinDir}/token";
    settings.agent = {
      # Placeholder; CIRCUS_AGENT__AGENT__NAME (the worker name) overrides it.
      name = "rworker-circus";
      runner_url = "circus+tls://circus.${runnerHost}.${config.domains.netbird}:8443";
      # Native only: the image could run aarch64 through qemu-user, but the
      # queue-runner would then place aarch64 builds here at emulation speed.
      systems = [ "x86_64-linux" ];
      supported_features = [
        "nixos-test"
        "benchmark"
        "big-parallel"
        "kvm"
      ];
      # The pool flavor (s1.2xlarge, 32 vCPUs): 4 builds of 8 cores.
      max_jobs = 4;
      cores = 8;
    };
  };
}
