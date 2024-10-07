let
  lib = import <nixpkgs/lib>;

  authorizedKeysContent = lib.strings.fileContents (
    builtins.fetchurl {
      url = "https://github.com/pschmitt.keys";
      sha256 = "16524539mfl0jnwgqqi714zvkwv8s6gsmrc52kkx46ar4p6ms9yg";
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
