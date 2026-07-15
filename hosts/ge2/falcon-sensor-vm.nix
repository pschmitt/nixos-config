{ config, inputs, ... }:
{
  sops.secrets."crowdstrike/customerId".sopsFile = ../../secrets/shared.sops.yaml;

  services.falcon-sensor-vm = {
    enable = true;
    package = inputs.self.nixosConfigurations.falcon-sensor-vm.config.system.build.vm;
    customerIdFile = config.sops.secrets."crowdstrike/customerId".path;
  };
}
