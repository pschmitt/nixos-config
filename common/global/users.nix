{
  imports = [
    ./users/root.nix
    ./users/pschmitt.nix
  ];

  users.mutableUsers = false;
}
