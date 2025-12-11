{
  config,
  inputs,
  lib,
  ...
}:
{
  networking.useDHCP = lib.mkDefault true;

  # NOTE Below will *NOT* work!
  # sops.secrets = {
  #   "ssh/initrd_host_keys/ed25519/privkey" = {
  #     sopsFile = config.custom.sopsFile;
  #     path = "/etc/ssh/initrd.sops/ssh_host_ed25519_key";
  #   };
  #   "ssh/initrd_host_keys/rsa/privkey" = {
  #     sopsFile = config.custom.sopsFile;
  #     path = "/etc/ssh/initrd.sops/ssh_host_rsa_key";
  #   };
  #   "ssh/initrd_host_keys/ed25519/pubkey" = {
  #     sopsFile = config.custom.sopsFile;
  #     path = "/etc/ssh/initrd.sops/ssh_host_ed25519_key.pub";
  #   };
  #   "ssh/initrd_host_keys/rsa/pubkey" = {
  #     sopsFile = config.custom.sopsFile;
  #     path = "/etc/ssh/initrd.sops/ssh_host_rsa_key.pub";
  #   };
  # };

  boot.initrd = {
    enable = true;
    # NOTE the command to unlock is: $ systemd-tty-ask-password-agent
    systemd = {
      enable = true;
      emergencyAccess = true;

      # network.enable = true;
    };

    # availableKernelModules = [ "r8169" ];

    network = {
      enable = true;
      flushBeforeStage2 = lib.mkDefault false;
      ssh = {
        enable = true;
        port = 22;
        inherit (config.mainUser) authorizedKeys;
        # authorizedKeys =
        #   with lib;
        #   concatLists (
        #     mapAttrsToList (
        #       name: user: if elem "wheel" user.extraGroups then user.openssh.authorizedKeys.keys else [ ]
        #     ) config.users.users
        #   );
        hostKeys = [
          # WARNING the host keys in initrd are stored in plain text
          # "/etc/ssh/ssh_host_rsa_key"
          # "/etc/ssh/ssh_host_ed25519_key"

          # NOTE sops-nix does *not* support initrd secrets
          # "/run/secrets/ssh/initrd_host_keys/ed25519/privkey"
          # "/run/secrets/ssh/initrd_host_keys/rsa/privkey"

          "/etc/ssh/initrd/ssh_host_rsa_key"
          "/etc/ssh/initrd/ssh_host_ed25519_key"
        ];
      };
    };
  };

  imports = [ inputs.luks-ssh-unlock.nixosModules.default ];
  services.luks-ssh-unlock = {
    enable = true;
    activationScript.enable = true;
  };
}
