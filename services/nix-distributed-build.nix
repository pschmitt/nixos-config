{ config, ... }:
{
  nix = {
    distributedBuilds = true;
    buildMachines = [
      {
        hostName = "rofl-09.brkn.lol";
        protocol = "ssh-ng";
        sshUser = "nix-remote-builder";
        sshKey = config.sops.secrets."ssh/nix-remote-builder/privkey".path;
        # NOTE we rely on the public keys being setup by programs.ssh.knownHosts
        # ssh rofl-09.brkn.lol base64 -w0 /etc/ssh/ssh_host_ed25519_key.pub
        # publicHostKey = "c3NoLWVkMjU1MTkgQUFBQUMzTnphQzFsWkRJMU5URTVBQUFBSU0xUlF1RDEyK0NMNU56SkhyVmdlNDl1SzlReVBsSVNvYlFHNU1OZ0laSG8gcm9vdEByb2ZsLTA5Cg==";
        systems = [ "x86_64-linux" ];
        maxJobs = 2;
        speedFactor = 1;
        supportedFeatures = [
          "nixos-test"
          "benchmark"
          "big-parallel"
        ];
      }
      {
        hostName = "rofl-03.brkn.lol";
        protocol = "ssh-ng";
        sshUser = "nix-remote-builder";
        sshKey = config.sops.secrets."ssh/nix-remote-builder/privkey".path;
        # NOTE we rely on the public keys being setup by programs.ssh.knownHosts
        # ssh rofl-03.brkn.lol base64 -w0 /etc/ssh/ssh_host_ed25519_key.pub
        # publicHostKey = "c3NoLWVkMjU1MTkgQUFBQUMzTnphQzFsWkRJMU5URTVBQUFBSUwvbStwRCtUc1NISnhTSFVIb3ltSHZxZXZGcnFPbWZBQmo3QWMxaFMzVFEgcm9vdEByb2ZsLTAzCg==";
        systems = [
          "aarch64-linux"
          "x86_64-linux"
        ];
        maxJobs = 14;
        speedFactor = 3;
        supportedFeatures = [
          "nixos-test"
          "benchmark"
          "big-parallel"
        ];
      }
    ];
    # optional, useful when the builder has a faster internet connection than yours
    extraOptions = ''
      builders-use-substitutes = true
    '';
  };
}
