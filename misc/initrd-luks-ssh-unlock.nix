{ config, lib, ... }: {
  networking.useDHCP = lib.mkDefault true;

  boot.initrd = {
    enable = true;
    # NOTE the command to unlock is systemd-tty-ask-password-agent
    systemd = {
      enable = true;
      # network.enable = true;
      emergencyAccess = true;
    };
    # availableKernelModules = [ "r8169" ];
    network = {
      enable = true;
      flushBeforeStage2 = lib.mkDefault false;
      ssh = {
        enable = true;
        port = 22;
        authorizedKeys = config.custom.authorizedKeys;
        # authorizedKeys = with lib; concatLists (mapAttrsToList (name: user: if elem "wheel" user.extraGroups then user.openssh.authorizedKeys.keys else [ ]) config.users.users);
        # hostKeys = [
        #   "/etc/ssh/ssh_host_rsa_key"
        #   "/etc/ssh/ssh_host_ed25519_key"
        # ];
        ignoreEmptyHostKeys = true;
      };
    };

    # secrets = {
    #   "/etc/ssh/ssh_host_ed25519_key" = "/etc/ssh/ssh_host_ed25519_key";
    #   "/etc/ssh/ssh_host_rsa_key" = "/etc/ssh/ssh_host_rsa_key";
    # };
  };

}
