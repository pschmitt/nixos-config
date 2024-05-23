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
  version = "b5a4db5e0247afbaa52e955993986aaed4575b85";

  src = fetchFromGitHub {
    owner = "pschmitt";
    repo = "${pname}";
    rev = "${version}";
    hash = "sha256-1BtrN2r3DKvGVU7bhl77uYEt0ZGiTrYpz/eOugmFNwk=";
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
