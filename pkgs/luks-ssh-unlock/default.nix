{
  lib,
  stdenv,
  fetchFromGitHub,
  makeWrapper,
  curl,
  jq,
  gnugrep,
  netcat-gnu,
  openssh,
}:

stdenv.mkDerivation rec {
  pname = "luks-ssh-unlock";
  version = "0c45e04a2f64522a2e12843fe1b2df3d0e07aab2";

  src = fetchFromGitHub {
    owner = "pschmitt";
    repo = "${pname}";
    rev = "${version}";
    hash = "sha256-wxh3AjMcPwYrkQnWfQHR3Lmfpax6WjwncU/Q+jLQK18=";
  };

  nativeBuildInputs = [ makeWrapper ];

  installPhase = ''
    mkdir -p $out/bin
    cp $src/luks-ssh-unlock.sh $out/bin/luks-ssh-unlock
    chmod +x $out/bin/luks-ssh-unlock

    wrapProgram $out/bin/luks-ssh-unlock --prefix PATH : ${
      lib.makeBinPath [
        curl
        gnugrep
        jq
        netcat-gnu
        openssh
      ]
    }
  '';

  meta = with lib; {
    description = "Auto-unlock remote hosts via SSH and Kubernetes";
    homepage = "https://github.com/pschmitt/luks-ssh-unlock";
    license = licenses.gpl3Only;
    maintainers = with maintainers; [ pschmitt ];
    mainProgram = "luks-ssh-unlock";
    platforms = platforms.all;
  };
}
