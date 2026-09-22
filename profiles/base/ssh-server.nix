{
  config,
  lib,
  ...
}:
{
  # OpenSSH server
  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = true;
      KbdInteractiveAuthentication = true;
      PermitRootLogin = "prohibit-password";
      # Let clients pick the bind address (e.g. 0.0.0.0)
      GatewayPorts = "clientspecified";
    };
    sftpServerExecutable = "internal-sftp";
    extraConfig = ''
      AcceptEnv TERM_SSH_CLIENT
    '';
  };

  networking.firewall = {
    allowedTCPPorts = lib.mkBefore [ 22 ];
    allowedUDPPortRanges = [
      {
        # mosh
        from = 60000;
        to = 61000;
      }
    ];
  };

  users.users.root.openssh.authorizedKeys.keys = config.mainUser.authorizedKeys;
}
