{ inputs, ... }: {
  imports = [
    inputs.hardware.nixosModules.common-pc-laptop-acpi_call
    ./network.nix
    ../../misc/nix-remote-build.nix
  ];

  services.logind.lidSwitchExternalPower = "ignore";
}
