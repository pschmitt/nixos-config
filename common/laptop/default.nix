{ pkgs, inputs, ... }: {
  imports = [
    inputs.hardware.nixosModules.common-pc-laptop-acpi_call
  ];

  services.logind.lidSwitchExternalPower = "ignore";
}
