{ pkgs, lib }:

with pkgs;

stdenv.mkDerivation {
  pname = "pschmitt-dev";
  version = "2024-10-17";

  src = fetchFromGitHub {
    owner = "pschmitt";
    repo = "pschmitt.dev";
    rev = "main";
    sha256 = "sha256-MjXrCG1hYpSUQx8DQQX2hFv7ptdnEzP4j88lexr5a9M=";
  };

  buildInputs = [ ];

  installPhase = ''
    mkdir -p $out
    cp -r * $out/
  '';

  meta = with lib; {
    description = "Personal website of pschmitt";
    homepage = "https://github.com/pschmitt/pschmitt.dev";
    license = licenses.gpl3Only;
    maintainers = with maintainers; [ pschmitt ];
  };
}
