{ config, pkgs, ... }: {
  # Enable SSH in the boot process.
  systemd.services.sshd.wantedBy =
    pkgs.lib.mkForce [ "multi-user.target" ];
  users.users.root.openssh.authorizedKeys.keys = config.custom.authorizedKeys;
  isoImage.squashfsCompression = "gzip -Xcompression-level 1";
  networking = {
    useDHCP = true;
    nameservers = [ "1.1.1.1" "8.8.8.8" ];
  };
}
