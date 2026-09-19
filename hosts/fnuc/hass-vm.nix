{
  imports = [ ../../services/home-assistant-vm.nix ];

  services.home-assistant-vm = {
    enable = true;
    physicalInterface = "eno1";
    bridgeMac = "1c:69:7a:0f:e5:fe";
    domainXml = ./home-assistant.xml;
    autostart = true;
  };
}
