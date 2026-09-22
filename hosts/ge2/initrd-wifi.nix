{
  imports = [ ../../services/initrd-luks-ssh-unlock.nix ];

  initrd.wifi = {
    enable = true;
    interfaceName = "wlp0s20f3";
  };
}
