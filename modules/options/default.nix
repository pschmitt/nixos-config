{
  imports = [
    ./custom/authelia.nix
    ./custom/crowdstrike.nix
    ./custom/home-assistant-sshfs.nix
    ./custom/luks-ssh-unlock-fleet.nix
    ./initrd/wifi.nix
    ./services/harmonia.nix
    ./services/home-assistant-vm.nix
    ./services/kvm-usb-passthrough.nix
    ./services/mail-autoconfig.nix
    ./services/nfs-client.nix
    ./services/nfs-server.nix
    ./services/ppd-react.nix
    ./services/watchyourlan.nix
  ];
}
