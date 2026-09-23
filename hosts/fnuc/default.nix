{
  imports = [
    ../../profiles/features/network/ha-sshfs.nix
    ../../profiles/specializations/homelab-server

    ../../services/browser-mcp-chromium-container.nix
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
    ./services.nix
  ];
}
