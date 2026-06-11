{
  # create a wireshark wrapper
  programs.wireshark = {
    enable = true;
    usbmon.enable = true;
  };
}
