{ config, ... }:

let
  hostname = config.networking.hostName;
in
{
  age = {
    secrets = {
      ssh-privkey.file = ../../secrets/${hostname}/nix-ssh-key-rofl-01.age;
      # ssh-pubkey.file = ../../secrets/${hostname}/nix-ssh-key-rofl-01.pub.age;
    };
  };

  nix = {
    distributedBuilds = true;
    buildMachines = [
      {
        hostName = "rofl-01";
        protocol = "ssh-ng";
        sshUser = "ubuntu";
        sshKey = config.age.secrets.ssh-privkey.path;
        publicHostKey = "c3NoLWVkMjU1MTkgQUFBQUMzTnphQzFsWkRJMU5URTVBQUFBSUwrcTVrZ1o5TVRmYnpvbnE1MGZMTmRrV3UxZmlyVlJKaU5iSzhBUDJpekggcm9vdEByb2ZsaW5zdGFuY2UtMDEK";
        systems = [ "x86_64-linux" ];
        maxJobs = 4;
        speedFactor = 2;
        supportedFeatures = [ "nixos-test" "benchmark" "big-parallel" ];
      }
    ];
  };
}
