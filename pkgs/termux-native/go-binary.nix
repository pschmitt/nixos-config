{
  lib,
  pkgs,
  package,
  binary,
}:
let
  buildGoModule = import ./build-go-module.nix { inherit pkgs; };
in
buildGoModule {
  pname = "${lib.getName package}-termux";
  inherit (package) version src vendorHash;

  env.CGO_ENABLED = "0";
  tags = [ "timetzdata" ];
  ldflags = package.ldflags or [ ];

  preBuild = ''
    export GOOS=android
    export GOARCH=arm64
  '';

  doCheck = false;
  doInstallCheck = false;

  installPhase = ''
    runHook preInstall
    install -Dm0755 "$GOPATH/bin/android_arm64/${binary}" "$out/bin/${binary}"
    runHook postInstall
  '';

  allowedReferences = [ ];
  passthru.termuxNative = {
    files = [ "bin/${binary}" ];
    binaries = [ "bin/${binary}" ];
  };
  meta = lib.removeAttrs package.meta [ "outputsToInstall" ] // {
    mainProgram = binary;
  };
}
