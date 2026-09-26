{
  lib,
  runCommand,
  go,
}:

runCommand "nixpp-termux"
  {
    nativeBuildInputs = [ go ];
    allowedReferences = [ ];
    meta = {
      description = "Small Nix binary-cache client for Termux-managed outputs";
    };
  }
  ''
    export CGO_ENABLED=0
    export GOOS=android
    export GOARCH=arm64
    export GOTOOLCHAIN=local
    export GOWORK=off
    export GOCACHE="$TMPDIR/go-cache"
    cd ${lib.cleanSource ./../../android/nixpp}
    mkdir -p "$out/bin"
    go build -trimpath -buildvcs=false -tags timetzdata -ldflags='-s -w' -o "$out/bin/nixpp" .
  ''
