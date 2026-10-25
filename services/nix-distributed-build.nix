{ config, ... }:
{
  nix = {
    distributedBuilds = true;
    buildMachines = [
      {
        hostName = "rofl-13.${config.domains.main}";
        protocol = "ssh-ng";
        sshUser = "nix-remote-builder";
        sshKey = config.sops.secrets."ssh/nix-remote-builder/privkey".path;
        # NOTE we rely on the public keys being setup by programs.ssh.knownHosts
        # ssh rofl-13.${config.domains.main} base64 -w0 /etc/ssh/ssh_host_ed25519_key.pub
        # publicHostKey = "c3NoLWVkMjU1MTkgQUFBQUMzTnphQzFsWkRJMU5URTVBQUFBSUwvbStwRCtUc1NISnhTSFVIb3ltSHZxZXZGcnFPbWZBQmo3QWMxaFMzVFEgcm9vdEByb2ZsLTAzCg==";
        systems = [
          "aarch64-linux"
          "x86_64-linux"
        ];
        maxJobs = 28;
        speedFactor = 3;
        supportedFeatures = [
          "nixos-test"
          "benchmark"
          "big-parallel"
        ];
      }
      {
        hostName = "rofl-14.${config.domains.main}";
        protocol = "ssh-ng";
        sshUser = "nix-remote-builder";
        sshKey = config.sops.secrets."ssh/nix-remote-builder/privkey".path;
        # NOTE we rely on the public keys being setup by programs.ssh.knownHosts
        # ssh rofl-13.${config.domains.main} base64 -w0 /etc/ssh/ssh_host_ed25519_key.pub
        # publicHostKey = "c3NoLWVkMjU1MTkgQUFBQUMzTnphQzFsWkRJMU5URTVBQUFBSUwvbStwRCtUc1NISnhTSFVIb3ltSHZxZXZGcnFPbWZBQmo3QWMxaFMzVFEgcm9vdEByb2ZsLTAzCg==";
        systems = [
          "aarch64-linux"
          "x86_64-linux"
        ];
        maxJobs = 28;
        speedFactor = 3;
        supportedFeatures = [
          "nixos-test"
          "benchmark"
          "big-parallel"
        ];
      }
      {
        hostName = "rofl-15.${config.domains.main}";
        protocol = "ssh-ng";
        sshUser = "nix-remote-builder";
        sshKey = config.sops.secrets."ssh/nix-remote-builder/privkey".path;
        # NOTE we rely on the public keys being setup by programs.ssh.knownHosts
        systems = [
          "aarch64-linux"
          "x86_64-linux"
        ];
        maxJobs = 28;
        speedFactor = 3;
        supportedFeatures = [
          "nixos-test"
          "benchmark"
          "big-parallel"
        ];
      }
      {
        hostName = "rofl-16.${config.domains.main}";
        protocol = "ssh-ng";
        sshUser = "nix-remote-builder";
        sshKey = config.sops.secrets."ssh/nix-remote-builder/privkey".path;
        # NOTE we rely on the public keys being setup by programs.ssh.knownHosts
        systems = [
          "aarch64-linux"
          "x86_64-linux"
        ];
        maxJobs = 28;
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
