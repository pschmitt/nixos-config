{
  fetchzip,
  lib,
  stdenvNoCC,
}:
let
  src = fetchzip {
    url = "https://raw.githubusercontent.com/jorge-lip/udocker-builds/6c15741787b8f5591e0aa44d06aab67d9370a9ce/tarballs/udocker-englib-1.2.11.tar.gz";
    hash = "sha256-oxiBkBq3X0iZzpg2VUXSN9aKDnb70xQUqTigcJ2Vcq8=";
    stripRoot = false;
  };
in
stdenvNoCC.mkDerivation {
  pname = "udocker-engines";
  version = "1.2.11";
  dontUnpack = true;
  dontBuild = true;
  dontConfigure = true;
  dontStrip = true;

  installPhase = ''
    mkdir -p "$out/bin" "$out/lib" "$out/share/doc"
    cp -a "${src}/udocker_dir/bin/"*arm64* "$out/bin/"
    cp -a "${src}/udocker_dir/lib/"*arm64.so "${src}/udocker_dir/lib/VERSION" "$out/lib/"
    cp -a "${src}/udocker_dir/doc/." "$out/share/doc/"
  '';

  meta = {
    description = "Prebuilt udocker execution tools and libraries";
    homepage = "https://github.com/jorge-lip/udocker-builds";
    license = [
      lib.licenses.asl20
      lib.licenses.gpl2Only
      lib.licenses.gpl3Only
      lib.licenses.lgpl21Plus
    ];
    platforms = [ "aarch64-linux" ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
}
