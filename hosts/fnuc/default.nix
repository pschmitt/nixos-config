{
  imports = [
    ../../profiles/features/network/ha-sshfs.nix
    ../../profiles/specializations/homelab-server
    ../../profiles/headless-browsers.nix

    ../../services/codex-ha-bridge.nix
    ../../services/go-hass-agent.nix
    ../../services/harmonia.nix
    ../../services/kubeconfig-update.nix

    ./authorized-keys.nix
    ./backups.nix
    ./disk-config.nix
    ./hardware-configuration.nix
    ./home-manager.nix
    ./monit.nix
    ./networking.nix
    ./prompt.nix
    ./rescue-ssh.nix
    ./resource-control.nix
    ./services.nix
  ];

  # Pinned per host: bumping it changes stateful service defaults.
  # https://nixos.org/manual/nixos/stable/options#opt-system.stateVersion
  system.stateVersion = "25.11";
}
