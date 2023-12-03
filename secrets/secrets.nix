let
  authorizedKeys = builtins.readFile (builtins.fetchurl {
    url = "https://github.com/pschmitt.keys";
    sha256 = "0z65rk873yc2bl6fk5y2czin260s5f5cqnzcw51bxyvshdwvp0kg";
  });

in
{
  "secret.age".publicKeys = [ authorizedKeys ];

  "ge2/restic-repository.age".publicKeys = [ authorizedKeys ];
  "ge2/restic-password.age".publicKeys = [ authorizedKeys ];
  "ge2/restic-env.age".publicKeys = [ authorizedKeys ];

  "x13/restic-password.age".publicKeys = [ authorizedKeys ];
  "x13/restic-repository.age".publicKeys = [ authorizedKeys ];
  "x13/restic-env.age".publicKeys = [ authorizedKeys ];
}
