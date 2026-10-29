{
  imports = [
    ../../profiles/features/network/ha-sshfs.nix
    ../../profiles/headless-browsers.nix
    ../../profiles/specializations/homelab-server
    ../../services/codex-ha-bridge.nix
    ../../services/go-hass-agent.nix
    ../../services/harmonia.nix
    ../../services/kubeconfig-update.nix

    ./agent-limits.nix
    ./authorized-keys.nix
    ./backups.nix
    ./browser-daemon.nix
    ./disk-config.nix
    ./hardware-configuration.nix
    ./home-manager.nix
    ./hypruse-remote.nix
    ./memory-snapshot.nix
    ./monit.nix
    ./networking.nix
    ./nix-cache-mirror.nix
    ./prompt.nix
    ./rescue-ssh.nix
    ./resource-control.nix
    ./services.nix
    ./zsh.nix
  ];

  # Pinned per host: bumping it changes stateful service defaults.
  # https://nixos.org/manual/nixos/stable/options#opt-system.stateVersion
  system.stateVersion = "25.11";
}
