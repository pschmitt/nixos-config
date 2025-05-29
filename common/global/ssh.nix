{ ... }:
{

  # https://github.com/nix-community/srvos/blob/main/nixos/common/well-known-hosts.nix
  # Avoid TOFU MITM with github by providing their public key here.
  programs.ssh.knownHosts = {
    "github.com".hostNames = [ "github.com" ];
    "github.com".publicKey =
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl";

    "gitlab.com".hostNames = [ "gitlab.com" ];
    "gitlab.com".publicKey =
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAfuCHKVTjquxvt6CM6tdG4SLp1Btn/nOeHHE5UOzRdf";

    "git.sr.ht".hostNames = [ "git.sr.ht" ];
    "git.sr.ht".publicKey =
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMZvRd4EtM7R+IHVMWmDkVU3VLQTSwQDSAvW0t2Tkj60";

    fnuc-ed25519 = {
      hostNames = [
        "fnuc.brkn.lol"
        "fnuc.nb.brkn.lol"
        "fnuc.ts.brkn.lol"
        "fnuc.snake-eagle.ts.net"
        "fnuc.netbird.cloud"
      ];
      publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMUasZ5NmpBE1LDa/sdD4F9dhlB4DpCUY0g2kQpSCmfo";
    };

    fnuc-rsa = {
      hostNames = [
        "fnuc.brkn.lol"
        "fnuc.nb.brkn.lol"
        "fnuc.ts.brkn.lol"
        "fnuc.snake-eagle.ts.net"
        "fnuc.netbird.cloud"
      ];
      publicKey = "fnuc ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQCxPqTGClmwptv+dPHd0NBFmpp4WjVP8/D1r3rFu6d/JDQ6/hk5PWqu+dGrNLh5FLamNXRK5LWG2LDftCGC2lAcTWzFqIt9PDT019vj/idpBpZd/PQOwnQ03YED1IsPH+KVHjp9PG/VkNL1m2FdHciCvz9bh/U5DFvAiCzhCGgNB2JdGvEL3gi9TXTQx95vMNCc0bvEF1KNZV+VGhxIwdTT2Y/CKtcjkZUc+ERa/jhZ3mmdMSvubvMyKfrpQ3GO9PNEb1To0OybjcgmbpuJpXbAAtnyJIxurSm+Mwx1KAxVtoi/40Fp2MDuLjN2R96iqRpLjihwxaBZN/J3Slc4BIkWYB6EhI6vPTHS5ZaanrnmFQw/HzQnNKegZMr8oilj1iw+IpTC78mIvGQXQdHfxPWAbTebTgeYTDOFLZWA0LUfqLHX6Z72o4thm1UBSYa3Hs+IOsBSVNuwMBpvdxcGzJoTN7WFj4XLtxqIIc3Epe4yuyZCwgwLHAqvBJZkYmVPYb8=";
    };

    rofl-03-ed25519 = {
      hostNames = [
        "rofl-03.brkn.lol"
        "rofl-03.nb.brkn.lol"
        "rofl-03.ts.brkn.lol"
        "rofl-03.snake-eagle.ts.net"
        "rofl-03.netbird.cloud"
      ];
      publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIL/m+pD+TsSHJxSHUHoymHvqevFrqOmfABj7Ac1hS3TQ";
    };

    rofl-03-rsa = {
      hostNames = [
        "rofl-03.brkn.lol"
        "rofl-03.nb.brkn.lol"
        "rofl-03.ts.brkn.lol"
        "rofl-03.snake-eagle.ts.net"
        "rofl-03.netbird.cloud"
      ];
      publicKey = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQC2+NpD/TdP9/Itq46RmocRplaLVx1AIWri4M95+39jfllUzWjy+S2zVG6/xpw7iynKOzQG7tNU4QGeYiCNhqhGDBGB9O1urAuBLbizisJvRC3aQwg6+9fPFmtcpjgHjCyvJcV7dP/90KG1n2ABElxzqpVXpd/Le1i2cHplsbA6gY61NKmmxkG+Bni1mz6nf1a4xu7iWuoWFFjbV57ElbRoP5DM9TOAgP4lwcMdrtB1Bzpu+eLD3/to88iFrCBilkADlSPfITi4rUAAX3bzfAeWOHPyibXBTRmH8jEEYQnI3sVmT72zKz5jUoH3ZP0D8r7v8bcRKCUyQrJeejsGmCIRKr8FR00aLvsA3g4zuM1jBXN4lSfgTuyps4/9YcnrR2Lofd/IAKdVb89VEENrLE7kqPCGf7sdgRH76yYvz0q03IzJqCQ96qPfuRbmi0Nb6PHLU8u5WpcKugq/YwhMBqgjntIMkQmb+aSEAwiTjTpgg2l4sJ06iXCMWmvvFmNoPWk=";
    };

    rofl-09-ed25519 = {
      hostNames = [
        "rofl-09.brkn.lol"
        "rofl-09.nb.brkn.lol"
        "rofl-09.ts.brkn.lol"
        "rofl-09.snake-eagle.ts.net"
        "rofl-09.netbird.cloud"
      ];
      publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIM1RQuD12+CL5NzJHrVge49uK9QyPlISobQG5MNgIZHo";
    };

    rofl-09-rsa = {
      hostNames = [
        "rofl-09.brkn.lol"
        "rofl-09.nb.brkn.lol"
        "rofl-09.ts.brkn.lol"
        "rofl-09.snake-eagle.ts.net"
        "rofl-09.netbird.cloud"
      ];
      publicKey = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQCsnM7oDZn6crEsYMIMUQ3flFp6vbMCAz+wWzxahUGdvrpUNjDt5qbfBQFjIyfLgiF+xgI1Vrk7iBReLZ5cGoXBfAv2O/CuA8SeMD073PyEH/j6wxhSXNT+yWh6aWOQvqY7ql7Bxn9hUKGyHJFLJmOoewk/fMBnot7gBF0hbsIhqxbTgU5MAgQJCn4vn2GMZUbJqHYuHK5nbXC8zGfI2UZjoLFyz/UMR7+68qrPiuxVepU19+9iVcCWmRhS0JPQUcHeCXy5jsn/Qz02bqESltclRpseofPXIq/WKhFioBJgB+1ds0++bO0bS35j/Sj+9MHvqF6uc3jPoR9Fw3F208gxPYwcki3QbpDSrcodvBeOw798wXmdehuFY/fHM2lwAFLGOWJ3O7wc/Y8UY9jGKlpa55QEvkpCuDvewb84VXe2/7x1lDyjHqQjky+KxE/9mrp2VqVIVZvw00qo/48+AZsMHtH6dEN1oRYXNS9cxFUb+94kxQO1UNWem42kr/9sCV8=";
    };

    oci-03-ed25519 = {
      hostNames = [
        "oci-03.brkn.lol"
        "oci-03.nb.brkn.lol"
        "oci-03.ts.brkn.lol"
        "oci-03.snake-eagle.ts.net"
        "oci-03.netbird.cloud"
      ];
      publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFD3RzcAixrG9tfq0qlpvQky3ViwA+4PJyhkQZ1iNj+G";
    };

    oci-03-rsa = {
      hostNames = [
        "oci-03.brkn.lol"
        "oci-03.nb.brkn.lol"
        "oci-03.ts.brkn.lol"
        "oci-03.snake-eagle.ts.net"
        "oci-03.netbird.cloud"
      ];
      publicKey = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQDynCgmEqPJkcnQtSCyZveZDM2nBiT232h+Pr9jt6pk/tH41jTFtRzGtimglUZlyoPmdXsgxmqID21yaYiXjPNbsGRXzdQXhp6GSnkY/VLtuwVlGC3SbAnhck6696AJPNpwIePTvrhjS1KSH3bugDRbjzH2EbUXmsKwqU37CL+oQAEwGzZYYQc7YNfAxGWtNUchRDIuKDZoUsTMydcNCm4Z/pZozDzAVZcJj9zWAse9VlHYnjla/gmXFoZjAciSyTbL3TGxWkTQ6//aoJJ++qF5jM3Lj5LfItinVAfyWsNf/8l6zHYZVO+pAcHD+nUHdf86/GSrMksl1xVY/6Ya9q1dwnPvy0PJqRk6vVU/fEw2sc41EV7+2NADV8nxOOZWY1uAHjaX3623KnTI4DaoNBG3GzNuMLA4RTluBEYISTQi7RC0gv+Xx5OmB1WK1VRXQz55/Stmz1RRa3cUx3iKPVdjIDzySAZT6Ez7M9U8252mJ6E6+Tfi4qmuail3BkpVqic=";
    };
  };
}
