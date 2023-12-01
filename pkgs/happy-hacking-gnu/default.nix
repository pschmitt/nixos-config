{
  lib
, stdenv
, fetchFromGitLab
, cmake
, udev
}:

stdenv.mkDerivation rec {
  pname = "happy-hacking-gnu";
  version = "0.2.1";

  src = fetchFromGitLab {
    owner = "dom";
    repo = "happy-hacking-gnu";
    rev = version;
    hash = "sha256-BCrczONdMJrHhROj213vXcj0qqDCYlC6SZTqxn9maS4=";
    fetchSubmodules = true;
  };

  nativeBuildInputs = [
    cmake
    udev
  ];

  installPhase = ''
    mkdir -p "$out/bin"
    cp hhg "$out/bin"
  '';

  meta = with lib; {
    description = "A free, open-source alternative to the HHKB Keymap Tool provided by PFU";
    homepage = "https://gitlab.com/dom/happy-hacking-gnu";
    license = licenses.unlicense;
    maintainers = with maintainers; [ pschmitt ];
    mainProgram = "happy-hacking-gnu";
    platforms = platforms.all;
  };
}
