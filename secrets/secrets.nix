let
  lib = import <nixpkgs/lib>;

  authorizedKeysContent = lib.strings.fileContents(builtins.fetchurl {
    url = "https://github.com/pschmitt.keys";
    sha256 = "0qcixq2zsh6p4xzxmjdl7bh13wyyv479sxhb0g2qg0qa6wg6qa49";
  });

  authorizedKeys = lib.filter (key: key != "") (lib.splitString "\n" authorizedKeysContent);

  hostKeys = [
    # ge2
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHxUgJAJlondg55FtQ1ez73QEiS3MR7u40K2+2SsJVQe"
    "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQCHmTs8/SMZtsprKdU1UE/07JXkCmlO/pUhQJRa34Ly7zlJAe3P+nEpqdzoMzmVBxkw+t0/FD58pHwZqY2P5xp2HqeSwEFc/OJRGufN+Y0shdizG2lRGP+b8a7ek/xrgM2COSVJyYvVnY0NujsLKI5nRyXM0HLz1QS9DdMy4CxRn6QGS40EIQVTmGxNjA12lVIG/PwRfp9aqLccBJ0NYpm+7O5fYwLKG5ldw5zuiBZPbdfyIOOPR13i4Yc6u9a1JWWeBFvYt8HgYX460VbXDlDpvcjLeWC4dt7h/DOOtfRYBMg1odp6XvIz6fXCaDU85gpwPEAQ3eVwdlcodAY+kY4pFk8QuvtJsCT16SQhcxv80/myjRqyA3ghRSomjsQIeXMuws7OBjHdgqpnTsUSyZdwE5GsOtc9gZ0e1Rv1bDwp8Rn+HMR8/ZnsmdEeNYZdP21s4fL0sE3wn8868RFSctLjfWuznS/w60nLHrtxNwUHZXISOSLKBGMHiDJFS/JuOJy9O0rUEfbHevGa3AEA5oWIgw7dli6LPOlTQGDdITOhWFppWAwgmV/Qqj66HGhtPHEr2uey8vHVkK/B+TwwxmQZW9CjdnGhliTlDRClrZJ9tSndrChZlYHp2xMQS+TgStiBxO603F7rgrxYw0lUYA7USNf5iE8GN8x++K8Z9ERttQ=="
    # x13
    "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQDOqfxGLVsNU2P6JjzoLQnyxVCMXPUY62tAp0IoL0TDwK5kae3MMyg0dMZjIPybLMtpTCsBGwaKKFtJgGXUea9XxSVFJN7uvL2/UN4aIFs7Ef4u2JoHjcDS4A7E0TrZlT85ejamiduDbSMdh9tSWjUAXT4PTqxUWQfxWwni4vL6Rr0Jw6TmvBcsMv6zwFDG3ImA6gNUyfIFnXaLo/7WDHecDW05aKT213a3oQTOgJWMOHQtgEUYruSmencdjSkDx2BpS9fzZA7nRMm3A+fCoNlsD9EE8yw36K5AU4cD5sQ3dzPIEV7rqKZWh08mhaKMmuRiRmJMNGsOXsyt8M2bvPWTymqKbFGF3FShZjdExGj281UA3ax+rmXq+Jxr1RJj6OSjVQKrFu74NCB/LoNAcCThbtswgdoJGaXZVWdfAjLup69FFw8y1nLhpCUjEORUCdYyabkIIezh+Mj8RGmtV0rNgHnrukp8w4D2ACa9vY8Z2naccAWvOrlfDfamsrLkAMc="
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAII/PReiXvGknx3dHACrDg0ApbI7X57JhHaSAbHbKPfff"
  ];

  recipients = authorizedKeys ++ hostKeys;

in
{
  "secret.age".publicKeys = recipients;

  "ge2/nix-netrc.age".publicKeys = recipients;
  "ge2/nix-ssh-key-rofl-01.age".publicKeys = recipients;
  "ge2/nix-ssh-key-rofl-01.pub.age".publicKeys = recipients;
  "ge2/restic-repository.age".publicKeys = recipients;
  "ge2/restic-password.age".publicKeys = recipients;
  "ge2/restic-env.age".publicKeys = recipients;

  "x13/nix-netrc.age".publicKeys = recipients;
  "x13/nix-ssh-key-rofl-01.age".publicKeys = recipients;
  "x13/nix-ssh-key-rofl-01.pub.age".publicKeys = recipients;
  "x13/restic-password.age".publicKeys = recipients;
  "x13/restic-repository.age".publicKeys = recipients;
  "x13/restic-env.age".publicKeys = recipients;

  "rofl-02/luks-passphrase-root.age".publicKeys = recipients;
  "rofl-02/ssh_host_rsa_key.age".publicKeys = recipients;
  "rofl-02/ssh_host_rsa_key.pub.age".publicKeys = recipients;
  "rofl-02/ssh_host_ed25519_key.age".publicKeys = recipients;
  "rofl-02/ssh_host_ed25519_key.pub.age".publicKeys = recipients;
}
