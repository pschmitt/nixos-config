{ ... }: {
  sops = {
    defaultSopsFile = ../../secrets/shared.sops.yaml;
    age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
    age.generateKey = false;

    secrets = {
      "xmrig/env" = { }; # shared
    };
  };
}
