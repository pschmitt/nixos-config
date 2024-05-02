{ ... }: {

  # https://github.com/nix-community/srvos/blob/main/nixos/common/well-known-hosts.nix
  # Avoid TOFU MITM with github by providing their public key here.
  programs.ssh.knownHosts = {
    "github.com".hostNames = [ "github.com" ];
    "github.com".publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl";

    "gitlab.com".hostNames = [ "gitlab.com" ];
    "gitlab.com".publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAfuCHKVTjquxvt6CM6tdG4SLp1Btn/nOeHHE5UOzRdf";

    "git.sr.ht".hostNames = [ "git.sr.ht" ];
    "git.sr.ht".publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMZvRd4EtM7R+IHVMWmDkVU3VLQTSwQDSAvW0t2Tkj60";

    "rofl-02.heimat.dev".hostNames = [ "rofl-02.heimat.dev" ];
    "rofl-02.heimat.dev".publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHj1bwykYI4tC4kt3Rd4QAOV2D1srlcQ14NLB9w3JBXp";

    "rofl-03.heimat.dev".hostNames = [ "rofl-03.heimat.dev" ];
    "rofl-03.heimat.dev".publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIL/m+pD+TsSHJxSHUHoymHvqevFrqOmfABj7Ac1hS3TQ";

    "oci-03.heimat.dev".hostNames = [ "oci-03.heimat.dev" ];
    "oci-03.heimat.dev".publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFD3RzcAixrG9tfq0qlpvQky3ViwA+4PJyhkQZ1iNj+G";
  };

  # age-secrets = {
  #   ssh-pubkey-ed25519-rofl-02.file = ../../secrets/rofl-02/ssh_host_ed25519_key.pub.age;
  #   ssh-pubkey-ed25519-rofl-03.file = ../../secrets/rofl-03/ssh_host_ed25519_key.pub.age;
  #   ssh-pubkey-rsa-rofl-02.file = ../../secrets/rofl-02/ssh_host_rsa_key.pub.age;
  #   ssh-pubkey-rsa-rofl-03.file = ../../secrets/rofl-03/ssh_host_rsa_key.pub.age;
  # };

  # programs.ssh.knownHostsFiles = [
  #   (pkgs.writeText "rofl.keys")
  #   ''
  #   rofl-02.heimat.dev
  #   ''
  # ];
}
