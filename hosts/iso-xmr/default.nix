{
  config,
  lib,
  pkgs,
  ...
}:
{

  imports = [
    ../../services/xmr/xmrig-iso.nix
  ];

  isoImage.squashfsCompression = "gzip -Xcompression-level 1";

  # Enable SSH in the boot process.
  systemd.services.sshd.wantedBy = pkgs.lib.mkForce [ "multi-user.target" ];
  users.users.root.openssh.authorizedKeys.keys = config.custom.authorizedKeys ++ [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGvVATHmFG1p5JqPkM2lE7wxCO2JGX3N5h9DEN3T2fKM nixos-anywhere"
  ];
  networking = {
    useDHCP = lib.mkForce true;
    nameservers = [
      "1.1.1.1"
      "8.8.8.8"
    ];
  };

  environment.systemPackages = with pkgs; [
    htop
  ];

  # quiesce
  boot.kernelParams = [
    "quiet"
    "loglevel=0"
  ];

  # https://docs.kernel.org/core-api/printk-basics.html
  boot.kernel.sysctl."kernel.printk" = "0 4 1 7";

  services.journald.extraConfig = ''
    ForwardToConsole=no
    # TTYPath=
    MaxLevelConsole=emerg
    MaxLevelKMsg=emerg
    Storage=volatile
  '';
}
