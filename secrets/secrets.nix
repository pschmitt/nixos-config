let
  lib = import <nixpkgs/lib>;

  authorizedKeysContent = lib.strings.fileContents (builtins.fetchurl {
    url = "https://github.com/pschmitt.keys";
    sha256 = "0qcixq2zsh6p4xzxmjdl7bh13wyyv479sxhb0g2qg0qa6wg6qa49";
  });

  authorizedKeys = lib.filter (key: key != "") (lib.splitString "\n" authorizedKeysContent);

  # ssh-keyscan HOST 2>/dev/null | sed -r 's#[^ ]* +(.+)#"\1"#'
  hostKeys = [
    # ge2
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHxUgJAJlondg55FtQ1ez73QEiS3MR7u40K2+2SsJVQe"
    "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQCHmTs8/SMZtsprKdU1UE/07JXkCmlO/pUhQJRa34Ly7zlJAe3P+nEpqdzoMzmVBxkw+t0/FD58pHwZqY2P5xp2HqeSwEFc/OJRGufN+Y0shdizG2lRGP+b8a7ek/xrgM2COSVJyYvVnY0NujsLKI5nRyXM0HLz1QS9DdMy4CxRn6QGS40EIQVTmGxNjA12lVIG/PwRfp9aqLccBJ0NYpm+7O5fYwLKG5ldw5zuiBZPbdfyIOOPR13i4Yc6u9a1JWWeBFvYt8HgYX460VbXDlDpvcjLeWC4dt7h/DOOtfRYBMg1odp6XvIz6fXCaDU85gpwPEAQ3eVwdlcodAY+kY4pFk8QuvtJsCT16SQhcxv80/myjRqyA3ghRSomjsQIeXMuws7OBjHdgqpnTsUSyZdwE5GsOtc9gZ0e1Rv1bDwp8Rn+HMR8/ZnsmdEeNYZdP21s4fL0sE3wn8868RFSctLjfWuznS/w60nLHrtxNwUHZXISOSLKBGMHiDJFS/JuOJy9O0rUEfbHevGa3AEA5oWIgw7dli6LPOlTQGDdITOhWFppWAwgmV/Qqj66HGhtPHEr2uey8vHVkK/B+TwwxmQZW9CjdnGhliTlDRClrZJ9tSndrChZlYHp2xMQS+TgStiBxO603F7rgrxYw0lUYA7USNf5iE8GN8x++K8Z9ERttQ=="
    # x13
    "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQDOqfxGLVsNU2P6JjzoLQnyxVCMXPUY62tAp0IoL0TDwK5kae3MMyg0dMZjIPybLMtpTCsBGwaKKFtJgGXUea9XxSVFJN7uvL2/UN4aIFs7Ef4u2JoHjcDS4A7E0TrZlT85ejamiduDbSMdh9tSWjUAXT4PTqxUWQfxWwni4vL6Rr0Jw6TmvBcsMv6zwFDG3ImA6gNUyfIFnXaLo/7WDHecDW05aKT213a3oQTOgJWMOHQtgEUYruSmencdjSkDx2BpS9fzZA7nRMm3A+fCoNlsD9EE8yw36K5AU4cD5sQ3dzPIEV7rqKZWh08mhaKMmuRiRmJMNGsOXsyt8M2bvPWTymqKbFGF3FShZjdExGj281UA3ax+rmXq+Jxr1RJj6OSjVQKrFu74NCB/LoNAcCThbtswgdoJGaXZVWdfAjLup69FFw8y1nLhpCUjEORUCdYyabkIIezh+Mj8RGmtV0rNgHnrukp8w4D2ACa9vY8Z2naccAWvOrlfDfamsrLkAMc="
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAII/PReiXvGknx3dHACrDg0ApbI7X57JhHaSAbHbKPfff"
    # rofl-02
    "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQCn9xUKTdw83a9eiUAh4QNBBawp+FDfDfklbQms+8Y2B7r4PejtNELZRLPdcalAsqVJh8hS3G8i/7jzeLQXVkwJfUCgnM+19FIpvyBGoTvLxRfq5rpt2aaLo7i0g/C/9uo2I0do2kRETdODxHqng18DY2WzyaM84qlG9Xjv5NwVAK/Io7080tWc2QF5CzFA2E6j5EUPCmT4xsQdAUW5S3G7374RoPVOIEYeaf0P4tAcezktVRE3uUloQPMAYL6ty8hUaQY+aB5ZoTPJ4c+er4N2foGhrvZcmZSMzCnGpuR5A22pC7+z2G4wE++ppkc6bBbWWah+5xfuaSqxiYmFxaF/yyrXVYy41/uNLCYiIpZjvSw59CXMRUIx6O7fHD8MOg0DtZx+HTMA9ItyCSM9NexrBeol36THzOjHkYNkvwJ6ws/jhtcOjmzcbRgE2ysWjcQqlmnreEQgP1dfh3VUHyPWoDbclM/VX0vLy2tQ18YjNxx8c0aejVlLki30+o6ld/0="
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHj1bwykYI4tC4kt3Rd4QAOV2D1srlcQ14NLB9w3JBXp"
    # rofl-03
    "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQC2+NpD/TdP9/Itq46RmocRplaLVx1AIWri4M95+39jfllUzWjy+S2zVG6/xpw7iynKOzQG7tNU4QGeYiCNhqhGDBGB9O1urAuBLbizisJvRC3aQwg6+9fPFmtcpjgHjCyvJcV7dP/90KG1n2ABElxzqpVXpd/Le1i2cHplsbA6gY61NKmmxkG+Bni1mz6nf1a4xu7iWuoWFFjbV57ElbRoP5DM9TOAgP4lwcMdrtB1Bzpu+eLD3/to88iFrCBilkADlSPfITi4rUAAX3bzfAeWOHPyibXBTRmH8jEEYQnI3sVmT72zKz5jUoH3ZP0D8r7v8bcRKCUyQrJeejsGmCIRKr8FR00aLvsA3g4zuM1jBXN4lSfgTuyps4/9YcnrR2Lofd/IAKdVb89VEENrLE7kqPCGf7sdgRH76yYvz0q03IzJqCQ96qPfuRbmi0Nb6PHLU8u5WpcKugq/YwhMBqgjntIMkQmb+aSEAwiTjTpgg2l4sJ06iXCMWmvvFmNoPWk="
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIL/m+pD+TsSHJxSHUHoymHvqevFrqOmfABj7Ac1hS3TQ"
    # oci-03
    "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQDynCgmEqPJkcnQtSCyZveZDM2nBiT232h+Pr9jt6pk/tH41jTFtRzGtimglUZlyoPmdXsgxmqID21yaYiXjPNbsGRXzdQXhp6GSnkY/VLtuwVlGC3SbAnhck6696AJPNpwIePTvrhjS1KSH3bugDRbjzH2EbUXmsKwqU37CL+oQAEwGzZYYQc7YNfAxGWtNUchRDIuKDZoUsTMydcNCm4Z/pZozDzAVZcJj9zWAse9VlHYnjla/gmXFoZjAciSyTbL3TGxWkTQ6//aoJJ++qF5jM3Lj5LfItinVAfyWsNf/8l6zHYZVO+pAcHD+nUHdf86/GSrMksl1xVY/6Ya9q1dwnPvy0PJqRk6vVU/fEw2sc41EV7+2NADV8nxOOZWY1uAHjaX3623KnTI4DaoNBG3GzNuMLA4RTluBEYISTQi7RC0gv+Xx5OmB1WK1VRXQz55/Stmz1RRa3cUx3iKPVdjIDzySAZT6Ez7M9U8252mJ6E6+Tfi4qmuail3BkpVqic="
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFD3RzcAixrG9tfq0qlpvQky3ViwA+4PJyhkQZ1iNj+G"
  ];

  recipients = authorizedKeys ++ hostKeys;

in
{
  "secret.age".publicKeys = recipients;
  "tailscale-auth-key.age".publicKeys = recipients;

  "ssh-key-nix-remote-builder.age".publicKeys = recipients;
  "ssh-key-nix-remote-builder.pub.age".publicKeys = recipients;

  "ge2/nix-netrc.age".publicKeys = recipients;
  "ge2/restic-repository.age".publicKeys = recipients;
  "ge2/restic-password.age".publicKeys = recipients;
  "ge2/restic-env.age".publicKeys = recipients;

  "x13/nix-netrc.age".publicKeys = recipients;
  "x13/restic-password.age".publicKeys = recipients;
  "x13/restic-repository.age".publicKeys = recipients;
  "x13/restic-env.age".publicKeys = recipients;

  "rofl-02/luks-passphrase-root.age".publicKeys = recipients;
  "rofl-02/luks-passphrase-data.age".publicKeys = recipients;
  "rofl-02/ssh_host_rsa_key.age".publicKeys = recipients;
  "rofl-02/ssh_host_rsa_key.pub.age".publicKeys = recipients;
  "rofl-02/ssh_host_ed25519_key.age".publicKeys = recipients;
  "rofl-02/ssh_host_ed25519_key.pub.age".publicKeys = recipients;

  "rofl-03/luks-passphrase-root.age".publicKeys = recipients;
  "rofl-03/ssh_host_rsa_key.age".publicKeys = recipients;
  "rofl-03/ssh_host_rsa_key.pub.age".publicKeys = recipients;
  "rofl-03/ssh_host_ed25519_key.age".publicKeys = recipients;
  "rofl-03/ssh_host_ed25519_key.pub.age".publicKeys = recipients;

  "oci-03/luks-passphrase-root.age".publicKeys = recipients;
  "oci-03/ssh_host_rsa_key.age".publicKeys = recipients;
  "oci-03/ssh_host_rsa_key.pub.age".publicKeys = recipients;
  "oci-03/ssh_host_ed25519_key.age".publicKeys = recipients;
  "oci-03/ssh_host_ed25519_key.pub.age".publicKeys = recipients;
}
