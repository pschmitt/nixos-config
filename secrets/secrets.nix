let
  lib = import <nixpkgs/lib>;

  authorizedKeysContent = lib.strings.fileContents (
    builtins.fetchurl {
      url = "https://github.com/pschmitt.keys";
      sha256 = "1klbvs8mf0i69k349whd1gg6ibwrl5qwh8rpwb57w4sz3k18jy42";
    }
  );

  pschmitt = lib.filter (key: key != "") (lib.splitString "\n" authorizedKeysContent);

  # ssh-keyscan HOST 2>/dev/null | sed -r 's#[^ ]* +(.+)#"\1"#'
  rofl-02 = [ "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHj1bwykYI4tC4kt3Rd4QAOV2D1srlcQ14NLB9w3JBXp" ];
in
# servers = rofl-02;
# everyone = pschmitt ++ servers;
{
  "rofl-02/luks-passphrase-data.age".publicKeys = pschmitt ++ rofl-02;
}
