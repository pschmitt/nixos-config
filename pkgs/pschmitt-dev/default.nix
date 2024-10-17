{ pkgs, lib }:

with pkgs;

stdenv.mkDerivation {
  pname = "pschmitt-dev";
  version = "2024-10-17-2";

  src = fetchFromGitHub {
    owner = "pschmitt";
    repo = "pschmitt.dev";
    rev = "main";
    hash = "sha256-N/lhS5B2Oc/tvwf/gsVQuO8OXgPriG3VeDvxkly8Zig=";
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
