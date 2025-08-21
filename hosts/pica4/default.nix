{
  config,
  lib,
  ...
}:

{
  imports = [
    ../../common/global/dotfiles.nix
    ../../common/global/pschmitt.nix

    ./hardware-configuration.nix
    # ../../services/camera/pi-rtsp.nix
  ];

  # boot.zfs.enabled = lib.mkForce false;

  networking = {
    hostName = "pica4";
    wireless = {
      enable = true;
      userControlled.enable = true;
      # iwd.enable = true;
      networks = {
        "brkn-lan" = {
          psk = "curlbitechatte57";
        };
      };
    };
    useDHCP = true;

    networkmanager.enable = false;
    networkmanager.wifi.powersave = false;
  };

  # services.piRtsp.enable = true;
  # services.piRtsp.path = "/cam";

  # Minimal hardening & SSH if you PXE/serial-less manage these
  services.openssh.enable = true;
  users.users.root.openssh.authorizedKeys.keys = config.custom.authorizedKeys ++ [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGvVATHmFG1p5JqPkM2lE7wxCO2JGX3N5h9DEN3T2fKM nixos-anywhere"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICGaXDkL/WvelHGLTp0j19arX3l0TLXUsxMyMhJUIuu+ pschmitt@ge2"
  ];
}
