{
  pkgs,
  apiLevel ? 35,
  ndkVersion ? "27.2.12479018",
}:
let
  android = pkgs.androidenv.composeAndroidPackages {
    includeNDK = true;
    ndkVersions = [ ndkVersion ];
    platformVersions = [ ];
    buildToolsVersions = [ ];
    includeEmulator = false;
  };
  ndkRoot = "${android.ndk-bundle}/libexec/android-sdk/ndk-bundle";
  toolchain = "${ndkRoot}/toolchains/llvm/prebuilt/linux-x86_64/bin";
  triple = "aarch64-linux-android";
in
assert
  toString pkgs.pkgsCross.aarch64-android-prebuilt.stdenv.targetPlatform.androidSdkVersion
  == toString apiLevel;
{
  abi = "android-bionic";
  architecture = "aarch64";
  inherit
    apiLevel
    ndkRoot
    ndkVersion
    toolchain
    ;
  prefix = "/data/data/com.termux/files/usr";
  pkgs = pkgs.pkgsCross.aarch64-android-prebuilt;
  cc = "${toolchain}/${triple}${toString apiLevel}-clang";
  objcopy = "${toolchain}/llvm-objcopy";
  readelf = "${toolchain}/llvm-readelf";
  strip = "${toolchain}/llvm-strip";
  sysroot = "${ndkRoot}/toolchains/llvm/prebuilt/linux-x86_64/sysroot";
  sysrootLib = "${ndkRoot}/toolchains/llvm/prebuilt/linux-x86_64/sysroot/usr/lib/${triple}/${toString apiLevel}";
}
