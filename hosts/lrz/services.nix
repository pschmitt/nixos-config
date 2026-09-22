{
  services = {
    fwupd.enable = true;
    kvm-usb-passthrough.enable = true;
    watchyourlan.interfaces = [
      "hass-br0"
      "wlp2s0"
    ];
  };
}
