{
  imports = [ ./home-assistant-vm.nix ];

  services.watchyourlan.interfaces = [
    "hass-br0"
    "wlp0s20f3"
  ];
}
