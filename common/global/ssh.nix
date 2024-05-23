{ ... }:
{

  # https://github.com/nix-community/srvos/blob/main/nixos/common/well-known-hosts.nix
  # Avoid TOFU MITM with github by providing their public key here.
  programs.ssh.knownHosts = {
    "github.com".hostNames = [ "github.com" ];
    "github.com".publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl";

    "gitlab.com".hostNames = [ "gitlab.com" ];
    "gitlab.com".publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAfuCHKVTjquxvt6CM6tdG4SLp1Btn/nOeHHE5UOzRdf";

    "git.sr.ht".hostNames = [ "git.sr.ht" ];
    "git.sr.ht".publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMZvRd4EtM7R+IHVMWmDkVU3VLQTSwQDSAvW0t2Tkj60";

    rofl-02-ed25519 = {
      hostNames = [
        "rofl-02.heimat.dev"
        "rofl-02-ts.heimat.dev"
        "rofl-02.snake-eagle.ts.net"
        "rofl-02.netbird.cloud"
      ];
      publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHj1bwykYI4tC4kt3Rd4QAOV2D1srlcQ14NLB9w3JBXp";
    };

    rofl-02-rsa = {
      hostNames = [
        "rofl-02.heimat.dev"
        "rofl-02-ts.heimat.dev"
        "rofl-02.snake-eagle.ts.net"
        "rofl-02.netbird.cloud"
      ];
      publicKey = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQCn9xUKTdw83a9eiUAh4QNBBawp+FDfDfklbQms+8Y2B7r4PejtNELZRLPdcalAsqVJh8hS3G8i/7jzeLQXVkwJfUCgnM+19FIpvyBGoTvLxRfq5rpt2aaLo7i0g/C/9uo2I0do2kRETdODxHqng18DY2WzyaM84qlG9Xjv5NwVAK/Io7080tWc2QF5CzFA2E6j5EUPCmT4xsQdAUW5S3G7374RoPVOIEYeaf0P4tAcezktVRE3uUloQPMAYL6ty8hUaQY+aB5ZoTPJ4c+er4N2foGhrvZcmZSMzCnGpuR5A22pC7+z2G4wE++ppkc6bBbWWah+5xfuaSqxiYmFxaF/yyrXVYy41/uNLCYiIpZjvSw59CXMRUIx6O7fHD8MOg0DtZx+HTMA9ItyCSM9NexrBeol36THzOjHkYNkvwJ6ws/jhtcOjmzcbRgE2ysWjcQqlmnreEQgP1dfh3VUHyPWoDbclM/VX0vLy2tQ18YjNxx8c0aejVlLki30+o6ld/0=";
    };

    rofl-03-ed25519 = {
      hostNames = [
        "rofl-03.heimat.dev"
        "rofl-03-ts.heimat.dev"
        "rofl-03.snake-eagle.ts.net"
        "rofl-03.netbird.cloud"
      ];
      publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIL/m+pD+TsSHJxSHUHoymHvqevFrqOmfABj7Ac1hS3TQ";
    };

    rofl-03-rsa = {
      hostNames = [
        "rofl-03.heimat.dev"
        "rofl-03-ts.heimat.dev"
        "rofl-03.snake-eagle.ts.net"
        "rofl-03.netbird.cloud"
      ];
      publicKey = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQC2+NpD/TdP9/Itq46RmocRplaLVx1AIWri4M95+39jfllUzWjy+S2zVG6/xpw7iynKOzQG7tNU4QGeYiCNhqhGDBGB9O1urAuBLbizisJvRC3aQwg6+9fPFmtcpjgHjCyvJcV7dP/90KG1n2ABElxzqpVXpd/Le1i2cHplsbA6gY61NKmmxkG+Bni1mz6nf1a4xu7iWuoWFFjbV57ElbRoP5DM9TOAgP4lwcMdrtB1Bzpu+eLD3/to88iFrCBilkADlSPfITi4rUAAX3bzfAeWOHPyibXBTRmH8jEEYQnI3sVmT72zKz5jUoH3ZP0D8r7v8bcRKCUyQrJeejsGmCIRKr8FR00aLvsA3g4zuM1jBXN4lSfgTuyps4/9YcnrR2Lofd/IAKdVb89VEENrLE7kqPCGf7sdgRH76yYvz0q03IzJqCQ96qPfuRbmi0Nb6PHLU8u5WpcKugq/YwhMBqgjntIMkQmb+aSEAwiTjTpgg2l4sJ06iXCMWmvvFmNoPWk=";
    };

    oci-03-ed25519 = {
      hostNames = [
        "oci-03.heimat.dev"
        "oci-03-ts.heimat.dev"
        "oci-03.snake-eagle.ts.net"
        "oci-03.netbird.cloud"
      ];
      publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFD3RzcAixrG9tfq0qlpvQky3ViwA+4PJyhkQZ1iNj+G";
    };

    oci-03-rsa = {
      hostNames = [
        "oci-03.heimat.dev"
        "oci-03-ts.heimat.dev"
        "oci-03.snake-eagle.ts.net"
        "oci-03.netbird.cloud"
      ];
      publicKey = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQDynCgmEqPJkcnQtSCyZveZDM2nBiT232h+Pr9jt6pk/tH41jTFtRzGtimglUZlyoPmdXsgxmqID21yaYiXjPNbsGRXzdQXhp6GSnkY/VLtuwVlGC3SbAnhck6696AJPNpwIePTvrhjS1KSH3bugDRbjzH2EbUXmsKwqU37CL+oQAEwGzZYYQc7YNfAxGWtNUchRDIuKDZoUsTMydcNCm4Z/pZozDzAVZcJj9zWAse9VlHYnjla/gmXFoZjAciSyTbL3TGxWkTQ6//aoJJ++qF5jM3Lj5LfItinVAfyWsNf/8l6zHYZVO+pAcHD+nUHdf86/GSrMksl1xVY/6Ya9q1dwnPvy0PJqRk6vVU/fEw2sc41EV7+2NADV8nxOOZWY1uAHjaX3623KnTI4DaoNBG3GzNuMLA4RTluBEYISTQi7RC0gv+Xx5OmB1WK1VRXQz55/Stmz1RRa3cUx3iKPVdjIDzySAZT6Ez7M9U8252mJ6E6+Tfi4qmuail3BkpVqic=";
    };
  };
}
