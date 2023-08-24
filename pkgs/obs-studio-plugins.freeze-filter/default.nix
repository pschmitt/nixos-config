{ stdenv
, lib
, fetchFromGitHub
, cmake
, pkg-config
, obs-studio
, libuiohook
, qtbase
, xorg
, libxkbcommon
, libxkbfile
}:

stdenv.mkDerivation rec {
  pname = "freeze-filter";
  version = "0.3.3";
  src = fetchFromGitHub {
    owner = "exeldro";
    repo = "obs-freeze-filter";
    rev = "${version}";
    sha256 = "sha256-CaHBTfdk8VFjmiclG61elj35glQafgz5B4ENo+7J35o=";
    fetchSubmodules = true;
  };

  nativeBuildInputs = [ cmake pkg-config ];
  buildInputs = [
    obs-studio
    libuiohook
    qtbase
    xorg.libX11
    xorg.libXau
    xorg.libXdmcp
    xorg.libXtst
    xorg.libXext
    xorg.libXi
    xorg.libXt
    xorg.libXinerama
    libxkbcommon
    libxkbfile
  ];

  postInstall = ''
    mkdir -p $out/lib $out/share
    mv $out/obs-plugins/64bit $out/lib/obs-plugins
    rm -rf $out/obs-plugins
    mv $out/data $out/share/obs
  '';

  dontWrapQtApps = true;

  meta = with lib; {
    description = "Plugin for OBS Studio to freeze a source using a filter ";
    homepage = "https://github.com/exeldro/obs-freeze-filter";
    license = licenses.gpl2;
    platforms = platforms.linux;
    # never built on aarch64-linux since first introduction in nixpkgs
    broken = stdenv.isLinux && stdenv.isAarch64;
  };
}
