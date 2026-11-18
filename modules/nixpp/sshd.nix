{
  config,
  lib,
  pkgs,
  ...
}:
let
  home = config.home-manager.configuration.config;
  certificate = "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";
  keyNames = [
    "ssh/host_keys/ed25519/privkey"
    "ssh/host_keys/rsa/privkey"
  ];
  hostKey =
    name:
    lib.replaceStrings [ "%r" ] [ config.fullNix.sops.runtimeDir ] config.sops.secrets.${name}.path;
in
{
  sops = {
    age.sshKeyPaths = home.sops.age.sshKeyPaths;
    secrets = lib.genAttrs keyNames (_: { });
  };

  services.sshd.command = [
    "${pkgs.openssh}/bin/sshd"
    "-D"
    "-e"
    "-f"
    "/etc/ssh/sshd_config"
  ];

  environment.etc = {
    "ssh/sshd_config".text = ''
      Port 2222
      ${lib.concatMapStringsSep "\n" (name: "HostKey ${hostKey name}") keyNames}
      PidFile /tmp/sshd.pid
      AuthenticationMethods publickey
      PasswordAuthentication no
      KbdInteractiveAuthentication no
      PermitRootLogin no
      UsePAM no
      AllowUsers ${config.user.name}
      SetEnv PATH=${config.user.home}/.nix-profile/bin:/run/current-system/sw/bin:/bin:/usr/bin NIXPP_RUNTIME=/run/nixpp-runtime NIX_CONF_DIR=${home.xdg.configHome}/nix NIX_SSL_CERT_FILE=${certificate} SSL_CERT_FILE=${certificate}
      AuthorizedKeysFile /etc/ssh/authorized_keys %h/.ssh/authorized_keys
      Subsystem sftp internal-sftp
    '';
    "ssh/authorized_keys".text = lib.concatLines (
      builtins.filter (key: key != "") home.mainUser.authorizedKeys
    );
  };
}
