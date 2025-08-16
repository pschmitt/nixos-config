{
  lib,
  stdenv,
  fetchFromGitHub,
  makeWrapper,
  gawk,
  gnugrep,
  gnused,
  tmux,
}:

stdenv.mkDerivation rec {
  pname = "tmux-slay";
  version = "484510bb034876dcc066d00d65aab9a53da8451e";

  src = fetchFromGitHub {
    owner = "pschmitt";
    repo = "${pname}";
    rev = "${version}";
    hash = "sha256-ONVhx9KvnexxUnAFTtfZQuJEjQUHoFyWk6EgbxnZ8ng=";
  };

  nativeBuildInputs = [ makeWrapper ];

  installPhase = ''
    mkdir -p $out/bin
    cp $src/tmux-slay $out/bin/tmux-slay

    wrapProgram $out/bin/tmux-slay --prefix PATH : ${
      lib.makeBinPath [
        gawk
        gnugrep
        gnused
        tmux
      ]
    }
  '';

  meta = with lib; {
    description = "TMUX script to run commands in a background session. Similar to abduco/dtach.";
    homepage = "https://github.com/pschmitt/tmux-slay";
    license = licenses.gpl3Only;
    maintainers = with maintainers; [ pschmitt ];
    mainProgram = "tmux-slay";
    platforms = platforms.all;
  };
}
