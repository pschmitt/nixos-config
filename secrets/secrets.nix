let
  lib = import <nixpkgs/lib>;

  authorizedKeysContent = lib.strings.fileContents (
    builtins.fetchurl {
      url = "https://github.com/pschmitt.keys";
      sha256 = "0zf9ylqj6xnaf909zilzgvi1iid7ihxviyawfdw44iqfvj32znwd";
    }
  );

  pschmitt = lib.filter (key: key != "") (lib.splitString "\n" authorizedKeysContent);

  # sops decrypt --extract '["ssh"]["host_keys"]["ed25519"]["pubkey"]' ./hosts/<HOST>/secrets.sops.yaml
  # or: ssh-keyscan <HOST> 2>/dev/null | sed -r 's#[^ ]* +(.+)#"\1"#'
  rofl-02 = [ "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHj1bwykYI4tC4kt3Rd4QAOV2D1srlcQ14NLB9w3JBXp" ];
  rofl-07 = [ "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHD/CEqIWCE8kdL8OVlDml6vWing7Uo3XfBAds760deg" ];
in
# servers = rofl-02;
# everyone = pschmitt ++ servers;
{
  "rofl-02/luks-passphrase-data.age".publicKeys = pschmitt ++ rofl-02;
  "rofl-07/luks-passphrase-data.age".publicKeys = pschmitt ++ rofl-07;
}
