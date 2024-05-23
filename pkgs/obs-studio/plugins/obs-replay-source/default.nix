{
  stdenv,
  lib,
  fetchFromGitHub,
  cmake,
  obs-studio,
  qtbase,
  libcaption,
}:

stdenv.mkDerivation rec {
  pname = "obs-replay-source";
  version = "1.6.13";
  src = fetchFromGitHub {
    owner = "exeldro";
    repo = "obs-replay-source";
    rev = "${version}";
    sha256 = "sha256-i64rpIVnUplA9AKZtR3xeByeawca7B00kGmEcKi7DWQ=";
    fetchSubmodules = true;
  };

  nativeBuildInputs = [ cmake ];
  buildInputs = [
    libcaption
    obs-studio
    qtbase
  ];

  postInstall = ''
    mkdir -p $out/lib $out/share
    mv $out/obs-plugins/64bit $out/lib/obs-plugins
    rm -rf $out/obs-plugins
    mv $out/data $out/share/obs
  '';

  dontWrapQtApps = true;

  meta = with lib; {
    description = "Replay source for OBS studio";
    homepage = "https://github.com/exeldro/obs-replay-source";
    license = licenses.gpl2;
    platforms = platforms.linux;
    # never built on aarch64-linux since first introduction in nixpkgs
    broken = stdenv.isLinux && stdenv.isAarch64;
  };
}
