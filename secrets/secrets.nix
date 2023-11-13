let
  authorizedKeys = builtins.readFile (builtins.fetchurl {
    url = "https://github.com/pschmitt.keys";
    sha256 = "0z65rk873yc2bl6fk5y2czin260s5f5cqnzcw51bxyvshdwvp0kg";
  });

in
{
  "secret.age".publicKeys = [ authorizedKeys ];
  "ComicCode.tar.gz.age".publicKeys = [ authorizedKeys ];
}
