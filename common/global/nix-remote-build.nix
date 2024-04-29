{ config, ... }: {
  # age = {
  #   secrets = {
  #     ssh-pubkey-rofl-02.file = ../../secrets/rofl-02/ssh_host_ed25519_key.age;
  #     ssh-pubkey-rofl-03.file = ../../secrets/rofl-03/ssh_host_ed25519_key.age;
  #   };
  # };

  nix = {
    distributedBuilds = true;
    buildMachines = [
      {
        hostName = "rofl-02.heimat.dev";
        protocol = "ssh-ng";
        sshUser = "nix-remote-builder";
        sshKey = config.custom.sshKey;
        # base64 -w0 /etc/ssh/ssh_host_ed25519_key.pub
        publicHostKey = "c3NoLWVkMjU1MTkgQUFBQUMzTnphQzFsWkRJMU5URTVBQUFBSUhqMWJ3eWtZSTR0QzRrdDNSZDRRQU9WMkQxc3JsY1ExNE5MQjl3M0pCWHAgcHNjaG1pdHRAZ2UyCg==";
        systems = [ "x86_64-linux" ];
        maxJobs = 2;
        speedFactor = 1;
        supportedFeatures = [ "nixos-test" "benchmark" "big-parallel" ];
      }
      {
        hostName = "rofl-03.heimat.dev";
        protocol = "ssh-ng";
        sshUser = "nix-remote-builder";
        sshKey = config.custom.sshKey;
        # base64 -w0 /etc/ssh/ssh_host_ed25519_key.pub
        publicHostKey = "c3NoLWVkMjU1MTkgQUFBQUMzTnphQzFsWkRJMU5URTVBQUFBSUwvbStwRCtUc1NISnhTSFVIb3ltSHZxZXZGcnFPbWZBQmo3QWMxaFMzVFEgcm9vdEByb2ZsLTAzCg==";
        systems = [ "aarch64-linux" "x86_64-linux" ];
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
