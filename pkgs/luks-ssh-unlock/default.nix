{
  lib,
  stdenv,
  fetchFromGitHub,
  makeWrapper,
  curl,
  dig,
  jq,
  gnugrep,
  msmtp,
  netcat-gnu,
  openssh,
}:

stdenv.mkDerivation rec {
  pname = "luks-ssh-unlock";
  version = "870adcb2013ea946aa0b72c1b5eb6a9be7b367a9";

  src = fetchFromGitHub {
    owner = "pschmitt";
    repo = "${pname}";
    rev = "${version}";
    hash = "sha256-5dpn/zMmm9B/dVU3/NFcT6ZoJD4UJ2rSFY/9BqrPCw0=";
  };

  nativeBuildInputs = [ makeWrapper ];

  installPhase = ''
    mkdir -p $out/bin
    cp $src/luks-ssh-unlock.sh $out/bin/luks-ssh-unlock
    chmod +x $out/bin/luks-ssh-unlock

    wrapProgram $out/bin/luks-ssh-unlock --prefix PATH : ${
      lib.makeBinPath [
        dig
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
