{
  stdenv,
  lib,
  fetchFromGitHub,
  cmake,
  re2c,
}:

stdenv.mkDerivation rec {
  pname = "libcaption";
  version = "0.7";
  src = fetchFromGitHub {
    owner = "szatmary";
    repo = "libcaption";
    rev = "${version}";
    sha256 = "sha256-OBtxoFJF0cxC+kfSK8TIKIdLkmCh5WOJlI0fejnisJo=";
    fetchSubmodules = true;
  };

  nativeBuildInputs = [ cmake ];
  buildInputs = [ re2c ];

  # postInstall = ''
  # '';

  meta = with lib; {
    description = "Free open-source CEA608 / CEA708 closed-caption encoder/decoder";
    homepage = "https://github.com/szatmary/libcaption";
    license = licenses.mit;
    platforms = platforms.linux;
    # never built on aarch64-linux since first introduction in nixpkgs
    broken = stdenv.isLinux && stdenv.isAarch64;
  };
}
