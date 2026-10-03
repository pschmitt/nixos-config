{
  lib,
  buildGoModule,
}:

buildGoModule {
  pname = "nixpp-termux";
  version = "0.1.0";

  src = lib.cleanSource ./../../android/nixpp;
  vendorHash = null;

  env = {
    CGO_ENABLED = "0";
    GOTOOLCHAIN = "local";
    GOWORK = "off";
  };

  ldflags = [
    "-s"
    "-w"
  ];

  # buildGoModule derives GOOS/GOARCH from the Nix platform (Linux/amd64 here).
  # Override them only while building; its default check phase then runs tests
  # natively on the Linux builder.
  preBuild = ''
    export GOOS=android
    export GOARCH=arm64
  '';

  postBuild = ''
    unset GOOS GOARCH
  '';

  installPhase = ''
    runHook preInstall

    install -Dm0755 "$GOPATH/bin/android_arm64/nixpp" "$out/bin/nixpp"

    runHook postInstall
  '';

  allowedReferences = [ ];

  # Explicit export contract consumed by the Termux bundle builder. The
  # executable is statically linked for GOOS=android and has no Nix runtime
  # closure. Other packages may declare additional files under their output.
  passthru.termuxNative = {
    files = [ "bin/nixpp" ];
    binaries = [ "bin/nixpp" ];
  };

  meta = {
    description = "Small Nix binary-cache client for Termux-managed outputs";
    homepage = "https://github.com/pschmitt/nixos-config/tree/main/android/nixpp";
    mainProgram = "nixpp";
    maintainers = [ lib.maintainers.pschmitt ];
    platforms = lib.platforms.linux;
  };
}
