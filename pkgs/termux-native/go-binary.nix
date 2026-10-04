{
  lib,
  llvm,
  pkgs,
  package,
  binary,
  licenseFile ? null,
}:
let
  go = pkgs.go.overrideAttrs (old: {
    postPatch = (old.postPatch or "") + ''
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
package.overrideAttrs (old: {
  pname = "${lib.getName package}-termux";

  env = (old.env or { }) // {
    CGO_ENABLED = "0";
    GOOS = "android";
    GOARCH = "arm64";
  };

  nativeBuildInputs = builtins.filter (input: input != package.go) (old.nativeBuildInputs or [ ]) ++ [
    go
    llvm
  ];

  doCheck = false;
  doInstallCheck = false;
  dontStrip = true;
  allowedReferences = [ ];

  postInstall = (old.postInstall or "") + ''
    install -Dm0755 "$out/bin/android_arm64/${binary}" "$out/bin/${binary}"
    rm -rf "$out/bin/android_arm64"
    ${lib.optionalString (licenseFile != null) ''
      install -Dm0644 ${lib.escapeShellArg licenseFile} "$out/share/licenses/${binary}"
    ''}
  '';

  postFixup = (old.postFixup or "") + ''
    llvm-strip --strip-unneeded "$out/bin/${binary}"
  '';

  passthru = (old.passthru or { }) // {
    termuxNative = {
      abi = "android-bionic";
      files = [ "bin/${binary}" ] ++ lib.optional (licenseFile != null) "share/licenses/${binary}";
      binaries = [ "bin/${binary}" ];
    };
  };

  meta = (old.meta or { }) // {
    mainProgram = binary;
  };
})
