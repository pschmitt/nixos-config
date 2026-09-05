{
  imports = [
    ./users/root.nix
    ./users/pschmitt.nix
    # Hermes needs to be able to SSH into any host, no exceptions (see
    # services/hermes.nix). Hosts that skip profiles/global/users.nix
    # (falcon-sensor-vm, picaz) import ./users/hermes.nix directly instead.
    ./users/hermes.nix
  ];

  users.mutableUsers = false;
}
