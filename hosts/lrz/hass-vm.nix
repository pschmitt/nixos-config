{
  imports = [ ../../services/home-assistant-vm.nix ];

  # Staging copy of the HA VM. It is deliberately defined but never
  # autostarted; fnuc remains the production owner until the final cutover.
  services.home-assistant-vm = {
    enable = true;
    physicalInterface = "enp1s0f0";
    bridgeMac = "6c:4b:90:e4:73:8c";
    domainXml = ./home-assistant.xml;
    autostart = false;
  };
}
