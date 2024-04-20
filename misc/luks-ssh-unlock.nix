{ config, ... }: {
  boot.kernelParams = [ "ip=dhcp" ];
  boot.initrd = {
    enable = true;
    # NOTE the command to unlock is systemd-tty-ask-password-agent
    systemd.enable = true;
    # availableKernelModules = [ "r8169" ];
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
}
