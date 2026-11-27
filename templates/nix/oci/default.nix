_: {
  imports = [
    ../../profiles/specializations/server

    ./disk-config.nix
    ./hardware-configuration.nix
  ];

  hardware = {
    cattle = true;
    serverType = "oci";
  };

  networking = {
    firewall.enable = false;
  };

  # Pinned per host: bumping it changes stateful service defaults.
  # https://nixos.org/manual/nixos/stable/options#opt-system.stateVersion
  system.stateVersion = "26.05";
}
