{
  lib,
  inputs,
  pkgs,
}:
let
  system = pkgs.stdenv.hostPlatform.system;
  fenix = inputs.fenix.packages.${system};
  rustToolchain = fenix.combine [
    fenix.minimal.cargo
    fenix.minimal.rustc
    fenix.targets.aarch64-linux-android.latest.rust-std
  ];
  rustPlatform = pkgs.makeRustPlatform {
    cargo = rustToolchain;
    rustc = rustToolchain;
  };
  androidPkgs = import inputs.nixpkgs {
    inherit system;
    config = {
      allowUnfree = true;
      android_sdk.accept_license = true;
    };
  };
  android = androidPkgs.androidenv.composeAndroidPackages {
    includeNDK = true;
    ndkVersions = [ "27.2.12479018" ];
    platformVersions = [ ];
    buildToolsVersions = [ ];
    includeEmulator = false;
  };
  ndkRoot = "${android.ndk-bundle}/libexec/android-sdk/ndk-bundle";
  ndkBin = "${ndkRoot}/toolchains/llvm/prebuilt/linux-x86_64/bin";
in
rustPlatform.buildRustPackage {
  pname = "nixpp-termux";
  version = "0.2.0";

  src = lib.cleanSource ./../../android/nixpp;
  cargoLock.lockFile = ./../../android/nixpp/Cargo.lock;
  doCheck = false;
  env = {
    CARGO_TARGET_AARCH64_LINUX_ANDROID_LINKER = "${ndkBin}/aarch64-linux-android24-clang";
  };
  buildPhase = ''
    runHook preBuild
    cargo build --locked --offline --release --target aarch64-linux-android
    runHook postBuild
  '';
  installPhase = ''
    runHook preInstall
    install -Dm0755 target/aarch64-linux-android/release/nixpp "$out/bin/nixpp"
    runHook postInstall
  '';

  allowedReferences = [ ];

  # The target is Android/Bionic. Rust's standard library is supplied by the
  # cross platform toolchain; the RustCrypto dependencies are statically linked.
  passthru.termuxNative = {
    abi = "android-bionic";
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
