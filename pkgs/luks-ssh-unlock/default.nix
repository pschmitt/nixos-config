{
  lib,
  stdenv,
  fetchFromGitHub,
  makeWrapper,
  curl,
  jq,
  gnugrep,
  msmtp,
  netcat-gnu,
  openssh,
}:

stdenv.mkDerivation rec {
  pname = "luks-ssh-unlock";
  version = "e66eb08f230ce486cb2285ba11ba32c3a51eefb2";

  src = fetchFromGitHub {
    owner = "pschmitt";
    repo = "${pname}";
    rev = "${version}";
    hash = "sha256-VZS5yF54jqGyymRMykD2kFTpEXvUExDQzNhtMhyVVfk=";
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
        msmtp # for sendmail, TODO: determine the sendmail implementation?
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
