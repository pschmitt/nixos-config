{ config, ... }:
{
  imports = [
    ../../profiles/specializations/rofl-build-node
    ../../services/luks-ssh-unlock/push-client.nix
    ../../services/circus

    ./hardware-configuration.nix
    ./networking.nix
    ./prompt.nix
  ];

  sops.secrets."circus/pr-author-ids" = config.sops.mkHostSecret {
    owner = "circus";
    restartUnits = [ "circus-queue-runner.service" ];
  };

  # Circus CI (services/circus/README.md).
  services.circus = {
    consumerBuildRepositories = [
      "pschmitt/anika-blue"
      "pschmitt/browser-daemon"
      "pschmitt/circus"
      "pschmitt/jellysync"
      "pschmitt/luks-ssh-unlock"
      "pschmitt/monarch"
      "pschmitt/rbw"
      "pschmitt/rworker"
      "pschmitt/tagesschau"
      "pschmitt/teams-live"
      "pschmitt/termuxpp"
    ];
    # Agents reach the queue-runner on rofl-15.
    agent.runnerHost = "rofl-15";
    # Agents upload outputs straight to niks3's bucket (under circus/), so
    # ISO-sized NARs no longer stream through the queue-runner first.
    s3Upload.enable = true;
    # GitHub as the App circus-pschmitt: commit statuses (circus/<job>) and
    # the push/pull-request webhook.
    githubApp.enable = true;
    githubStatuses.enable = true;
    githubWebhook.enable = true;
    # Ephemeral agents on rworkers (rworker-circus image), scaled by the
    # autoscaler on rofl-10 (private services/rworker-circus-pool.nix).
    rworkerPool.enable = true;
    qemuOverflow.enable = true;
    # aarch64 builds of circusJobs on GitHub's arm runners (circus-builder.yml):
    # ephemeral agents started via workflow_dispatch with the App's token.
    githubActionsAgents = {
      enable = true;
      kvm.enable = true;
      pullRequestAuthorIdsFile = config.sops.secrets."circus/pr-author-ids".path;
      # Static agent from our fork (release-agent-aarch64.yml), matching the
      # pinned circus input.
      agentBinaryUrl = "https://github.com/pschmitt/circus/releases/download/v0.14.0-pschmitt.1/circus-agent-aarch64-linux";
      agentBinarySha256 = "e83a29b64b3f52d0f4401169ba70d08d0214155c39b6f10a145eab405f6cf0fa";
    };
    # Publish effects after green main builds.
    effects = {
      enable = true;
      dryRun = false;
    };
    stricknaniArtifactBridge.enable = true;
    monarchArtifactBridge.enable = true;
    circusArtifactBridge.enable = true;
    declaroidArtifactBridge.enable = true;
  };

  # Pinned per host: bumping it changes stateful service defaults.
  # https://nixos.org/manual/nixos/stable/options#opt-system.stateVersion
  system.stateVersion = "26.11";
}
