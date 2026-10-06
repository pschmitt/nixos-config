{
  hardware = {
    cattle = false;
    serverType = "oci";
  };

  # Keep /tmp mounted across NixOS switches; stopping tmp.mount drops D-Bus.
  boot.tmp.useTmpfs = true;
}
