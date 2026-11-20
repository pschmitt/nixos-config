{
  imports = [
    ../../profiles/specializations/rofl-build-node
    ../../services/circus

    ./hardware-configuration.nix
    ./networking.nix
    ./prompt.nix
  ];

  # Circus CI trial (services/circus/README.md): agents reach the
  # queue-runner on rofl-15.
  services.circus.agent.runnerHost = "rofl-15";

  # Pinned per host: bumping it changes stateful service defaults.
  # https://nixos.org/manual/nixos/stable/options#opt-system.stateVersion
  system.stateVersion = "26.11";
}
