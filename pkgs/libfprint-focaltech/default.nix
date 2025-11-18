# https://www.reddit.com/r/GPDPocket/comments/1jw4q26/gpd_pocket_4_nixos_fingerprint_driver/
# https://discourse.nixos.org/t/request-for-libfprint-port-for-2808-a658/55474
{
  stdenv,
  lib,
  # fetchurl,
  rpm,
  cpio,
  glib,
  gusb,
  pixman,
  libgudev,
  nss,
  libfprint,
  cairo,
  pkg-config,
  autoPatchelfHook,
  makePkgconfigItem,
  copyPkgconfigItems,
}:
let
  # The provided `.so`'s name in the binary package we fetch and unpack
  libso = "libfprint-2.so.2.0.0";
in
stdenv.mkDerivation rec {
  pname = "libfprint-focaltech";
  version = "1.94.9";

  src = ./libfprint-2-2_1.94.4+tod1_redhat_all_x64_20250219.install;
  # src = fetchurl {
  #   # url = "https://github.com/ftfpteams/focaltech-linux-fingerprint-driver/raw/refs/heads/main/Fedora_Redhat/libfprint-2-2_1.94.4+tod1_redhat_all_x64_20250219.install";
  #   url = ./libfprint-2-2_1.94.4+tod1_redhat_all_x64_20250219.install;
  #   sha256 = "0y7kb2mr7zd2irfgsmfgdpb0c7v33cb4hf3hfj7mndalma3xdhzn";  # Will help you fetch this in a sec
  # };

  nativeBuildInputs = [
    rpm
    cpio
    pkg-config
    autoPatchelfHook
    copyPkgconfigItems
  ];

  buildInputs = [
    stdenv.cc.cc
    glib
    gusb
    pixman
    nss
    libgudev
    libfprint
    cairo
  ];

  unpackPhase = ''
      runHook preUnpack
    echo "Extracting embedded tar.gz using sed"

    sed '1,/^main \$@/d' $src > libfprint.tar.gz

    mkdir extracted
    tar -xzf libfprint.tar.gz -C .
  '';

  # custom pkg-config based on libfprint's pkg-config
  pkgconfigItems = [
    (makePkgconfigItem rec {
      name = "libfprint-2";
      inherit version;
      inherit (meta) description;
      cflags = [ "-I${variables.includedir}/libfprint-2" ];
      libs = [
        "-L${variables.libdir}"
        "-lfprint-2"
      ];
      variables = rec {
        prefix = "${placeholder "out"}";
        includedir = "${prefix}/include";
        libdir = "${prefix}/lib";
      };
    })
  ];

  installPhase = ''
    runHook preInstall

    install -Dm444 usr/lib64/${libso} -t $out/lib

    # create this symlink as it was there in libfprint
    ln -s -T $out/lib/${libso} $out/lib/libfprint-2.so
    ln -s -T $out/lib/${libso} $out/lib/libfprint-2.so.2

    # get files from libfprint required to build the package
    cp -r ${libfprint}/lib/girepository-1.0 $out/lib
    cp -r ${libfprint}/include $out

    runHook postInstall
  '';

  meta = with lib; {
    description = "FocalTech libfprint driver (Fedora variant)";
    homepage = "https://github.com/ftfpteams/focaltech-linux-fingerprint-driver";
    platforms = platforms.linux;
    license = licenses.unfree; # Sadly
  };
}
