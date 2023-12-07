let
  lib = import <nixpkgs/lib>;

  authorizedKeysContent = lib.strings.fileContents(builtins.fetchurl {
    url = "https://github.com/pschmitt.keys";
    sha256 = "0z65rk873yc2bl6fk5y2czin260s5f5cqnzcw51bxyvshdwvp0kg";
  });

  authorizedKeys = lib.filter (key: key != "") (lib.splitString "\n" authorizedKeysContent);

  hostKeys = [
    # ge2
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHxUgJAJlondg55FtQ1ez73QEiS3MR7u40K2+2SsJVQe"
    # x13
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAII/PReiXvGknx3dHACrDg0ApbI7X57JhHaSAbHbKPfff"
  ];

  recipients = authorizedKeys ++ hostKeys;

in
{
  "secret.age".publicKeys = recipients;

  "ge2/restic-repository.age".publicKeys = recipients;
  "ge2/restic-password.age".publicKeys = recipients;
  "ge2/restic-env.age".publicKeys = recipients;

  "x13/restic-password.age".publicKeys = recipients;
  "x13/restic-repository.age".publicKeys = recipients;
  "x13/restic-env.age".publicKeys = recipients;
}
