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
  ];
  x13 = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAII/PReiXvGknx3dHACrDg0ApbI7X57JhHaSAbHbKPfff"
  ];
  lrz = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGMRoAq4Vh4benZeqOHl5eDPHNvMM5owOFvbDTSgcpcU root@lrz"
  ];
  rofl-02 = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHj1bwykYI4tC4kt3Rd4QAOV2D1srlcQ14NLB9w3JBXp"
  ];
  rofl-03 = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIL/m+pD+TsSHJxSHUHoymHvqevFrqOmfABj7Ac1hS3TQ"
  ];
  rofl-04 = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIoRaaTPSj+0h8FGwtWk9tXTfb3638Ft+AL0dcbN91/o root@rofl-04"
  ];
  rofl-05 = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIA1Ab8AhdwJLeT2ySUXRE1FNB0Ez8srtOAC+MvjRXNqF root@rofl-05"
  ];
  oci-03 = [
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
