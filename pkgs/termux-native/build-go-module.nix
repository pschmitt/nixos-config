{ pkgs }:
let
  go = pkgs.go.overrideAttrs (old: {
    postPatch =
      (old.postPatch or "")
      + "\n"
      + ''
          substituteInPlace src/net/lookup_unix.go \
          --replace-fail '${pkgs.iana-etc}/etc/protocols' \
            '/data/data/com.termux/files/usr/etc/protocols'
        substituteInPlace src/net/port_unix.go \
          --replace-fail '${pkgs.iana-etc}/etc/services' \
            '/data/data/com.termux/files/usr/etc/services'
        substituteInPlace src/mime/type_unix.go \
          --replace-fail '${pkgs.mailcap}/etc/mime.types' \
            '/data/data/com.termux/files/usr/etc/mime.types'
      '';
  });
in
pkgs.callPackage "${pkgs.path}/pkgs/build-support/go/module.nix" { inherit go; }
