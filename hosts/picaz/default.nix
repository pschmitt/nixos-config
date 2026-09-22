{
  imports = [
    ../../profiles/base/ntp.nix
    ../../profiles/base/sops.nix
    ../../profiles/base/ssh-server.nix
    ../../profiles/base/users/hermes.nix
    ../../profiles/base/users/root.nix

    ./camera.nix
    ./config-txt.nix
    ./console.nix
    ./hardware-configuration.nix
    ./hardware.nix
    ./networking.nix
    ./nix.nix
    ./packages.nix
    ./ssh.nix
    ./state.nix
    ./users.nix
  ];
}
