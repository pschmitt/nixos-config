let
  authorizedKeys = builtins.readFile (builtins.fetchurl {
    url = "https://github.com/pschmitt.keys";
    sha256 = "0kzafzw0bmpghrrm3fgsdrr6bl21p4ydgdvv4lwkszhpmb0rr4ys";
  });

in
{
  "secret.age".publicKeys = [ authorizedKeys ];
}
