{
  imports = [
    ../../profiles/specializations/rofl-build-node
    ../../services/circus

    ./hardware-configuration.nix
    ./networking.nix
    ./prompt.nix
  ];

  # Circus CI trial (services/circus/README.md).
  services.circus = {
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
  };

  # Pinned per host: bumping it changes stateful service defaults.
  # https://nixos.org/manual/nixos/stable/options#opt-system.stateVersion
  system.stateVersion = "26.11";
}
