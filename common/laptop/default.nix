{ inputs, ... }: {
  imports = [
    inputs.hardware.nixosModules.common-pc-laptop-acpi_call
    ./network.nix
  ];

  services.logind.lidSwitchExternalPower = "ignore";
}
