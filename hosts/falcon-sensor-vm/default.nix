{
  imports = [
    ./falcon-sensor.nix
    ./openssh.nix
    ./vm.nix
  ];

  system.stateVersion = "25.11";
}
