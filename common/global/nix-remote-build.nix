{ config, ... }: {
  age = {
    secrets = {
      ssh-privkey.file = ../../secrets/ssh-key-nix-remote-builder.age;
      # ssh-pubkey.file = ../../secrets/ssh-key-nix-remote-builder.pub.age;
    };
  };

  nix = {
    distributedBuilds = true;
    buildMachines = [
      {
        hostName = "rofl-03.heimat.dev";
        protocol = "ssh-ng";
        sshUser = "pschmitt";
        sshKey = config.age.secrets.ssh-privkey.path;
        # base64 -w0 /etc/ssh/ssh_host_ed25519_key.pub
        publicHostKey = "c3NoLWVkMjU1MTkgQUFBQUMzTnphQzFsWkRJMU5URTVBQUFBSUwvbStwRCtUc1NISnhTSFVIb3ltSHZxZXZGcnFPbWZBQmo3QWMxaFMzVFEgcm9vdEByb2ZsLTAzCg==";
        systems = [ "x86_64-linux" ];
        maxJobs = 8;
        speedFactor = 2;
        supportedFeatures = [ "nixos-test" "benchmark" "big-parallel" ];
      }
    ];
    # optional, useful when the builder has a faster internet connection than yours
    extraOptions = ''
      builders-use-substitutes = true
    '';
  };
}
