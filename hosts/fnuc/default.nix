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
    ./rescue-ssh.nix
    ./resource-control.nix
    ./services.nix
    ./zsh.nix
  ];
}
