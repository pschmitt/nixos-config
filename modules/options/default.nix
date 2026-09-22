{
  imports = [
    ./initrd/wifi.nix

    ./services/authelia.nix
    ./services/crowdstrike.nix
    ./services/harmonia.nix
    ./services/home-assistant-sshfs.nix
    ./services/home-assistant-vm.nix
    ./services/http-static.nix
    ./services/kvm-usb-passthrough.nix
    ./services/luks-ssh-unlock-fleet.nix
    ./services/mail-autoconfig.nix
    ./services/netbird.nix
    ./services/nfs-client.nix
    ./services/nfs-server.nix
    ./services/ppd-react.nix
    ./services/watchyourlan.nix
  ];
}
