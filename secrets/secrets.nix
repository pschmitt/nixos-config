let
  lib = import <nixpkgs/lib>;

  authorizedKeysContent = lib.strings.fileContents (builtins.fetchurl {
    url = "https://github.com/pschmitt.keys";
    sha256 = "0qcixq2zsh6p4xzxmjdl7bh13wyyv479sxhb0g2qg0qa6wg6qa49";
  });

  pschmitt = lib.filter (key: key != "") (lib.splitString "\n" authorizedKeysContent);

  # ssh-keyscan HOST 2>/dev/null | sed -r 's#[^ ]* +(.+)#"\1"#'
  ge2 = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHxUgJAJlondg55FtQ1ez73QEiS3MR7u40K2+2SsJVQe"
    "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQCHmTs8/SMZtsprKdU1UE/07JXkCmlO/pUhQJRa34Ly7zlJAe3P+nEpqdzoMzmVBxkw+t0/FD58pHwZqY2P5xp2HqeSwEFc/OJRGufN+Y0shdizG2lRGP+b8a7ek/xrgM2COSVJyYvVnY0NujsLKI5nRyXM0HLz1QS9DdMy4CxRn6QGS40EIQVTmGxNjA12lVIG/PwRfp9aqLccBJ0NYpm+7O5fYwLKG5ldw5zuiBZPbdfyIOOPR13i4Yc6u9a1JWWeBFvYt8HgYX460VbXDlDpvcjLeWC4dt7h/DOOtfRYBMg1odp6XvIz6fXCaDU85gpwPEAQ3eVwdlcodAY+kY4pFk8QuvtJsCT16SQhcxv80/myjRqyA3ghRSomjsQIeXMuws7OBjHdgqpnTsUSyZdwE5GsOtc9gZ0e1Rv1bDwp8Rn+HMR8/ZnsmdEeNYZdP21s4fL0sE3wn8868RFSctLjfWuznS/w60nLHrtxNwUHZXISOSLKBGMHiDJFS/JuOJy9O0rUEfbHevGa3AEA5oWIgw7dli6LPOlTQGDdITOhWFppWAwgmV/Qqj66HGhtPHEr2uey8vHVkK/B+TwwxmQZW9CjdnGhliTlDRClrZJ9tSndrChZlYHp2xMQS+TgStiBxO603F7rgrxYw0lUYA7USNf5iE8GN8x++K8Z9ERttQ=="
  ];
  x13 = [
    "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQDOqfxGLVsNU2P6JjzoLQnyxVCMXPUY62tAp0IoL0TDwK5kae3MMyg0dMZjIPybLMtpTCsBGwaKKFtJgGXUea9XxSVFJN7uvL2/UN4aIFs7Ef4u2JoHjcDS4A7E0TrZlT85ejamiduDbSMdh9tSWjUAXT4PTqxUWQfxWwni4vL6Rr0Jw6TmvBcsMv6zwFDG3ImA6gNUyfIFnXaLo/7WDHecDW05aKT213a3oQTOgJWMOHQtgEUYruSmencdjSkDx2BpS9fzZA7nRMm3A+fCoNlsD9EE8yw36K5AU4cD5sQ3dzPIEV7rqKZWh08mhaKMmuRiRmJMNGsOXsyt8M2bvPWTymqKbFGF3FShZjdExGj281UA3ax+rmXq+Jxr1RJj6OSjVQKrFu74NCB/LoNAcCThbtswgdoJGaXZVWdfAjLup69FFw8y1nLhpCUjEORUCdYyabkIIezh+Mj8RGmtV0rNgHnrukp8w4D2ACa9vY8Z2naccAWvOrlfDfamsrLkAMc="
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAII/PReiXvGknx3dHACrDg0ApbI7X57JhHaSAbHbKPfff"

  ];
  lrz = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGMRoAq4Vh4benZeqOHl5eDPHNvMM5owOFvbDTSgcpcU root@lrz"
  ];
  rofl-02 = [
    "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQCn9xUKTdw83a9eiUAh4QNBBawp+FDfDfklbQms+8Y2B7r4PejtNELZRLPdcalAsqVJh8hS3G8i/7jzeLQXVkwJfUCgnM+19FIpvyBGoTvLxRfq5rpt2aaLo7i0g/C/9uo2I0do2kRETdODxHqng18DY2WzyaM84qlG9Xjv5NwVAK/Io7080tWc2QF5CzFA2E6j5EUPCmT4xsQdAUW5S3G7374RoPVOIEYeaf0P4tAcezktVRE3uUloQPMAYL6ty8hUaQY+aB5ZoTPJ4c+er4N2foGhrvZcmZSMzCnGpuR5A22pC7+z2G4wE++ppkc6bBbWWah+5xfuaSqxiYmFxaF/yyrXVYy41/uNLCYiIpZjvSw59CXMRUIx6O7fHD8MOg0DtZx+HTMA9ItyCSM9NexrBeol36THzOjHkYNkvwJ6ws/jhtcOjmzcbRgE2ysWjcQqlmnreEQgP1dfh3VUHyPWoDbclM/VX0vLy2tQ18YjNxx8c0aejVlLki30+o6ld/0="
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHj1bwykYI4tC4kt3Rd4QAOV2D1srlcQ14NLB9w3JBXp"
  ];
  rofl-03 = [
    "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQC2+NpD/TdP9/Itq46RmocRplaLVx1AIWri4M95+39jfllUzWjy+S2zVG6/xpw7iynKOzQG7tNU4QGeYiCNhqhGDBGB9O1urAuBLbizisJvRC3aQwg6+9fPFmtcpjgHjCyvJcV7dP/90KG1n2ABElxzqpVXpd/Le1i2cHplsbA6gY61NKmmxkG+Bni1mz6nf1a4xu7iWuoWFFjbV57ElbRoP5DM9TOAgP4lwcMdrtB1Bzpu+eLD3/to88iFrCBilkADlSPfITi4rUAAX3bzfAeWOHPyibXBTRmH8jEEYQnI3sVmT72zKz5jUoH3ZP0D8r7v8bcRKCUyQrJeejsGmCIRKr8FR00aLvsA3g4zuM1jBXN4lSfgTuyps4/9YcnrR2Lofd/IAKdVb89VEENrLE7kqPCGf7sdgRH76yYvz0q03IzJqCQ96qPfuRbmi0Nb6PHLU8u5WpcKugq/YwhMBqgjntIMkQmb+aSEAwiTjTpgg2l4sJ06iXCMWmvvFmNoPWk="
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIL/m+pD+TsSHJxSHUHoymHvqevFrqOmfABj7Ac1hS3TQ"
  ];
  rofl-04 = [
    "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQC0FHaVoCo14CG22CEAabj2SYxAbQl/QxXOAAxLeKtiGfpvM9lTPYqT82os++JqlWrDw2qyxpm3YkyBt+OQx8iWKJJIGYrSJ0aHvjfkkCIQFkgp1/Q/Ur77dBP5IpiOal9D7Elc3bSMmpbAzNBfLn5CLjxjdd0DeMZV1ovbiO80DLDLbHaxlh5R4d6n21lqMVvct1CxDyhqZP6dF7+5wiZDE9MuMyyYqlZlm1G2ui0M1ujDkERQuoL9s1mfhVZ6P6eORvPBOyxjOFYjjMCXXMFse9Pesf22GezYaAEhyLH/fpPCyr3x6AaKT+ucpvVNRw8tpY941Yu+ehuvcqqlcio6q7Coi/AgAvvj6xORYpMif1A0sI/cts8hgRYyH0ckzxZrCC8j8XaT8GJOEePui4h/IMxkBoC9r2kiUWzfioKctAjQGvJrMQljbSaDn1OY2tHxrhMDGJJ4eX2UzxYkG0cExzRs9lm+fZjKTAbFt6TbGxQ5ZBSAqC2xZ9w9+x/C4o8= root@rofl-04"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIoRaaTPSj+0h8FGwtWk9tXTfb3638Ft+AL0dcbN91/o root@rofl-04"
  ];
  rofl-05 = [
    "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQCD74Bi4fOfhrwi3vsgY5Z4g4iQlKB4usKQaZwSqbapBmxq5H84mli5fg/hi8FA+IJzVDzXDo1YSVATPemJ1cG88o/2qt4/hanej8/4kz+LHWE0qkmW/tlFGPwIP6WIQpmmUYFt/YUn0b5Cz9MGez9ibQuaDlkjr+a1yzvdqWCibT4Rbojxag2yVAVP9wFrHDze/FYyTA7re16RbrESuad8bf4c6RjCHaBAvO5K3nLas75yxy0aiC6ax7+TuNXnAvFdmhBH+UjMGP460waV0wFFLXUM13VF4gBfNnmbxxuUOtG+RL54WmUvXtbq/tjUqE0VdJLEBViwEXgWEY8EoqZrMKFzyiKFzz/87QPoeeLCYtYfObzs4ZC7UP1lsuKa506URWtWwgHIf2N93HVfvKBKD8niOPV6XrC4b1aZk/6Lu1pXz7EDFDvl/W8enLQhB9gEmVmxjAG7fThFQHUflUfxa9Mo9K9+kpgTx1K6flt5GkQIR97R22ZBzWXdYavda6s= root@rofl-05"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIA1Ab8AhdwJLeT2ySUXRE1FNB0Ez8srtOAC+MvjRXNqF root@rofl-05"

  ];
  oci-03 = [
    "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQDynCgmEqPJkcnQtSCyZveZDM2nBiT232h+Pr9jt6pk/tH41jTFtRzGtimglUZlyoPmdXsgxmqID21yaYiXjPNbsGRXzdQXhp6GSnkY/VLtuwVlGC3SbAnhck6696AJPNpwIePTvrhjS1KSH3bugDRbjzH2EbUXmsKwqU37CL+oQAEwGzZYYQc7YNfAxGWtNUchRDIuKDZoUsTMydcNCm4Z/pZozDzAVZcJj9zWAse9VlHYnjla/gmXFoZjAciSyTbL3TGxWkTQ6//aoJJ++qF5jM3Lj5LfItinVAfyWsNf/8l6zHYZVO+pAcHD+nUHdf86/GSrMksl1xVY/6Ya9q1dwnPvy0PJqRk6vVU/fEw2sc41EV7+2NADV8nxOOZWY1uAHjaX3623KnTI4DaoNBG3GzNuMLA4RTluBEYISTQi7RC0gv+Xx5OmB1WK1VRXQz55/Stmz1RRa3cUx3iKPVdjIDzySAZT6Ez7M9U8252mJ6E6+Tfi4qmuail3BkpVqic="
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFD3RzcAixrG9tfq0qlpvQky3ViwA+4PJyhkQZ1iNj+G"
  ];
  oci-04 = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINV9A30ogk+ycIZRu0D7BadF2+oW1upg2dsk6q+JN4mv root@oci-04"
  ];

  servers = rofl-02 ++ rofl-03 ++ rofl-03 ++ rofl-04 ++ rofl-05 ++ oci-03 ++ oci-04 ++ lrz;
  laptops = ge2 ++ x13;
  hostKeys = laptops ++ servers;
  everyone = pschmitt ++ hostKeys;

in
{
  "mullvad-account.age".publicKeys = everyone;
  "netbird-netbird-io-setup-key.age".publicKeys = everyone;
  "netbird-wiit-setup-key.age".publicKeys = pschmitt ++ laptops;
  "tailscale-auth-key.age".publicKeys = everyone;
  "wallets.age".publicKeys = everyone;

  "mmonit-license.age".publicKeys = pschmitt ++ oci-03;
  "mmonit-monit-config.age".publicKeys = everyone;

  "ssh-key-nix-remote-builder.age".publicKeys = everyone;
  "ssh-key-nix-remote-builder.pub.age".publicKeys = everyone;

  "ge2/nix-netrc.age".publicKeys = pschmitt ++ ge2;
  "ge2/restic-env.age".publicKeys = pschmitt ++ ge2;
  "ge2/restic-password.age".publicKeys = pschmitt ++ ge2;
  "ge2/restic-repository.age".publicKeys = pschmitt ++ ge2;

  "x13/nix-netrc.age".publicKeys = pschmitt ++ x13;
  "x13/restic-env.age".publicKeys = pschmitt ++ x13;
  "x13/restic-password.age".publicKeys = pschmitt ++ x13;
  "x13/restic-repository.age".publicKeys = pschmitt ++ x13;

  # "fnuc/luks-passphrase-root.age".publicKeys = everyone;

  "lrz/luks-passphrase-root.age".publicKeys = pschmitt;
  "lrz/restic-env.age".publicKeys = pschmitt ++ lrz;
  "lrz/restic-password.age".publicKeys = pschmitt ++ lrz;
  "lrz/restic-repository.age".publicKeys = pschmitt ++ lrz;
  "lrz/ssh_host_ed25519_key.age".publicKeys = pschmitt ++ lrz;
  "lrz/ssh_host_ed25519_key.pub.age".publicKeys = pschmitt ++ lrz;
  "lrz/ssh_host_rsa_key.age".publicKeys = pschmitt ++ lrz;
  "lrz/ssh_host_rsa_key.pub.age".publicKeys = pschmitt ++ lrz;
  "lrz/msmtp-password-gmail.age".publicKeys = pschmitt ++ lrz;
  "lrz/msmtp-password-heimat-dev.age".publicKeys = pschmitt ++ lrz;

  "rofl-02/luks-passphrase-root.age".publicKeys = pschmitt;
  "rofl-02/luks-passphrase-data.age".publicKeys = pschmitt ++ rofl-02;
  "rofl-02/msmtp-password-gmail.age".publicKeys = pschmitt ++ rofl-02;
  "rofl-02/msmtp-password-heimat-dev.age".publicKeys = pschmitt ++ rofl-02;
  "rofl-02/restic-env.age".publicKeys = pschmitt ++ rofl-02;
  "rofl-02/restic-password.age".publicKeys = pschmitt ++ rofl-02;
  "rofl-02/restic-repository.age".publicKeys = pschmitt ++ rofl-02;
  "rofl-02/ssh_host_ed25519_key.age".publicKeys = pschmitt ++ rofl-02;
  "rofl-02/ssh_host_ed25519_key.pub.age".publicKeys = pschmitt ++ rofl-02;
  "rofl-02/ssh_host_rsa_key.age".publicKeys = pschmitt ++ rofl-02;
  "rofl-02/ssh_host_rsa_key.pub.age".publicKeys = pschmitt ++ rofl-02;

  "rofl-03/luks-passphrase-root.age".publicKeys = pschmitt;
  "rofl-03/msmtp-password-gmail.age".publicKeys = pschmitt ++ rofl-03;
  "rofl-03/msmtp-password-heimat-dev.age".publicKeys = pschmitt ++ rofl-03;
  "rofl-03/restic-env.age".publicKeys = pschmitt ++ rofl-03;
  "rofl-03/restic-password.age".publicKeys = pschmitt ++ rofl-03;
  "rofl-03/restic-repository.age".publicKeys = pschmitt ++ rofl-03;
  "rofl-03/ssh_host_ed25519_key.age".publicKeys = pschmitt ++ rofl-03;
  "rofl-03/ssh_host_ed25519_key.pub.age".publicKeys = pschmitt ++ rofl-03;
  "rofl-03/ssh_host_rsa_key.age".publicKeys = pschmitt ++ rofl-03;
  "rofl-03/ssh_host_rsa_key.pub.age".publicKeys = pschmitt ++ rofl-03;

  "rofl-04/luks-passphrase-root.age".publicKeys = pschmitt;
  "rofl-04/msmtp-password-gmail.age".publicKeys = pschmitt ++ rofl-04;
  "rofl-04/msmtp-password-heimat-dev.age".publicKeys = pschmitt ++ rofl-04;
  "rofl-04/restic-env.age".publicKeys = pschmitt ++ rofl-04;
  "rofl-04/restic-password.age".publicKeys = pschmitt ++ rofl-04;
  "rofl-04/restic-repository.age".publicKeys = pschmitt ++ rofl-04;
  "rofl-04/ssh_host_ed25519_key.age".publicKeys = pschmitt ++ rofl-04;
  "rofl-04/ssh_host_ed25519_key.pub.age".publicKeys = pschmitt ++ rofl-04;
  "rofl-04/ssh_host_rsa_key.age".publicKeys = pschmitt ++ rofl-04;
  "rofl-04/ssh_host_rsa_key.pub.age".publicKeys = pschmitt ++ rofl-04;

  "rofl-05/luks-passphrase-root.age".publicKeys = pschmitt;
  "rofl-05/msmtp-password-gmail.age".publicKeys = pschmitt ++ rofl-05;
  "rofl-05/msmtp-password-heimat-dev.age".publicKeys = pschmitt ++ rofl-05;
  "rofl-05/restic-env.age".publicKeys = pschmitt ++ rofl-05;
  "rofl-05/restic-password.age".publicKeys = pschmitt ++ rofl-05;
  "rofl-05/restic-repository.age".publicKeys = pschmitt ++ rofl-05;
  "rofl-05/ssh_host_ed25519_key.age".publicKeys = pschmitt ++ rofl-05;
  "rofl-05/ssh_host_ed25519_key.pub.age".publicKeys = pschmitt ++ rofl-05;
  "rofl-05/ssh_host_rsa_key.age".publicKeys = pschmitt ++ rofl-05;
  "rofl-05/ssh_host_rsa_key.pub.age".publicKeys = pschmitt ++ rofl-05;

  "oci-03/luks-passphrase-root.age".publicKeys = pschmitt;
  "oci-03/msmtp-password-gmail.age".publicKeys = pschmitt ++ oci-03;
  "oci-03/msmtp-password-heimat-dev.age".publicKeys = pschmitt ++ oci-03;
  "oci-03/restic-env.age".publicKeys = pschmitt ++ oci-03;
  "oci-03/restic-password.age".publicKeys = pschmitt ++ oci-03;
  "oci-03/restic-repository.age".publicKeys = pschmitt ++ oci-03;
  "oci-03/ssh_host_ed25519_key.age".publicKeys = pschmitt ++ oci-03;
  "oci-03/ssh_host_ed25519_key.pub.age".publicKeys = pschmitt ++ oci-03;
  "oci-03/ssh_host_rsa_key.age".publicKeys = pschmitt ++ oci-03;
  "oci-03/ssh_host_rsa_key.pub.age".publicKeys = pschmitt ++ oci-03;

  "oci-04/luks-passphrase-root.age".publicKeys = pschmitt;
  "oci-04/msmtp-password-gmail.age".publicKeys = pschmitt ++ oci-04;
  "oci-04/msmtp-password-heimat-dev.age".publicKeys = pschmitt ++ oci-04;
  "oci-04/restic-env.age".publicKeys = pschmitt ++ oci-04;
  "oci-04/restic-password.age".publicKeys = pschmitt ++ oci-04;
  "oci-04/restic-repository.age".publicKeys = pschmitt ++ oci-04;
  "oci-04/ssh_host_ed25519_key.age".publicKeys = pschmitt ++ oci-04;
  "oci-04/ssh_host_ed25519_key.pub.age".publicKeys = pschmitt ++ oci-04;
  "oci-04/ssh_host_rsa_key.age".publicKeys = pschmitt ++ oci-04;
  "oci-04/ssh_host_rsa_key.pub.age".publicKeys = pschmitt ++ oci-04;
}
