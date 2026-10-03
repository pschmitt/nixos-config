{
  dpkg,
  fetchurl,
  lib,
  openssl,
  runCommand,
}:
let
  version = "18.23.0";
  opensslVersion = "1:3.6.5";
  # Hashes are from the Termux aarch64 Packages index, pinned for this bundle.
  atuinDeb = fetchurl {
    url = "https://packages.termux.dev/apt/termux-main/pool/main/a/atuin/atuin_${version}_aarch64.deb";
    hash = "sha256-nt0dEYA7GIT1m0D+9UI6+uBWXbgEW/05AzT85Xpxnho=";
  };
  opensslDeb = fetchurl {
    url = "https://packages.termux.dev/apt/termux-main/pool/main/o/openssl/openssl_${opensslVersion}_aarch64.deb";
    hash = "sha256-ovt4VodeY+9rkEQnUuBZdIEzcsPKhtJROnjqQ8Z6D4s=";
  };
in
runCommand "atuin-termux-${version}"
  {
    nativeBuildInputs = [ dpkg ];
    allowedReferences = [ ];
    passthru.termuxNative = {
      files = [
        "bin/atuin"
        "lib/libcrypto.so.3"
        "lib/libssl.so.3"
        "share/licenses/atuin"
        "share/licenses/openssl"
      ];
      binaries = [ "bin/atuin" ];
    };
    meta = {
      description = "Magical shell history for native Termux";
      homepage = "https://atuin.sh/";
      license = [
        lib.licenses.mit
        lib.licenses.asl20
      ];
      mainProgram = "atuin";
    };
  }
  ''
    atuin_root="$TMPDIR/atuin"
    openssl_root="$TMPDIR/openssl"
    mkdir -p "$atuin_root" "$openssl_root"
    dpkg-deb -x ${atuinDeb} "$atuin_root"
    dpkg-deb -x ${opensslDeb} "$openssl_root"

    prefix="$atuin_root/data/data/com.termux/files/usr"
    openssl_prefix="$openssl_root/data/data/com.termux/files/usr"
    install -Dm0755 "$prefix/bin/atuin" "$out/bin/atuin"
    install -Dm0755 "$openssl_prefix/lib/libcrypto.so.3" "$out/lib/libcrypto.so.3"
    install -Dm0755 "$openssl_prefix/lib/libssl.so.3" "$out/lib/libssl.so.3"
    install -Dm0644 "$prefix/share/doc/atuin/LICENSE" "$out/share/licenses/atuin"
    tar -xOf ${openssl.src} --wildcards 'openssl-*/LICENSE.txt' \
      > "$TMPDIR/openssl-license"
    install -Dm0644 "$TMPDIR/openssl-license" "$out/share/licenses/openssl"
  ''
