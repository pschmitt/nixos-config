{ config, ... }:
let
  hostname = config.networking.hostName;
in
{
  boot.kernelParams = [ "ip=dhcp" ];
  boot.initrd = {
    enable = true;
    # availableKernelModules = [ "r8169" ];
    # systemd.users.root.shell = "/bin/cryptsetup-askpass";
    network = {
      enable = true;
      flushBeforeStage2 = true;
      ssh = {
        enable = true;
        port = 22;
        authorizedKeys = config.users.users.pschmitt.openssh.authorizedKeys.keys;
        hostKeys = [
          "/etc/ssh/ssh_host_rsa_key"
          "/etc/ssh/ssh_host_ed25519_key"
        ];
      };
    };
  };

  # Data volume
  age.secrets.luks-key-data.file = ../../secrets/${hostname}/luks-passphrase-data.age;

  environment.etc.crypttab.text = ''
    data UUID=371fa9e9-38f4-4022-bc96-227821c5eea7 ${config.age.secrets.luks-key-data.path}
  '';

  fileSystems."/mnt/data" = {
    device = "/dev/mapper/data";
    fsType = "btrfs";
  };
}
