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
  version = "621012f56711ba20ad4327b2f6c868c1edb7c6b1";

  src = fetchFromGitHub {
    owner = "pschmitt";
    repo = "${pname}";
    rev = "${version}";
    hash = "sha256-Fq4G1W17dvbihvZ7X4j50Uz0H2aJ0Mpe8N7YfhlN5ow=";
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
