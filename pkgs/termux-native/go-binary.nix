{
  lib,
  pkgs,
  package,
  binary,
  buildBinary ? binary,
  target,
  skipPostInstall ? false,
  skipPostFixup ? false,
  licenseFile ? null,
}:
let
  targetCC = target.cc;
  targetBintools = target.pkgs.stdenv.cc.bintools;
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
    CGO_ENABLED = "1";
    CC = targetCC;
    GOOS = "android";
    GOARCH = "arm64";
  };

  nativeBuildInputs = builtins.filter (input: input != package.go) (old.nativeBuildInputs or [ ]) ++ [
    go
    targetBintools
  ];

  preBuild = (old.preBuild or "") + ''
    export CC=${targetCC}
  '';

  doCheck = false;
  doInstallCheck = false;
  dontStrip = true;
  allowedReferences = [ ];
  ldflags = builtins.map (flag: if flag == "-static" then "-Wl,-z,relro" else flag) (
    old.ldflags or [ ]
  );

  postInstall = (if skipPostInstall then "" else (old.postInstall or "")) + ''
    install -Dm0755 "$out/bin/android_arm64/${buildBinary}" "$out/bin/${binary}"
    rm -rf "$out/bin/android_arm64"
    ${lib.optionalString (licenseFile != null) ''
      install -Dm0644 ${lib.escapeShellArg licenseFile} "$out/share/licenses/${binary}"
    ''}
  '';

  postFixup = (if skipPostFixup then "" else (old.postFixup or "")) + ''
    ${target.objcopy} --strip-unneeded "$out/bin/${binary}"
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
