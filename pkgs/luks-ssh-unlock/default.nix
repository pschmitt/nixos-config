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
  version = "d4eab4290da593b0da6dcd8a0cd0d731f01f3668";

  src = fetchFromGitHub {
    owner = "pschmitt";
    repo = "${pname}";
    rev = "${version}";
    hash = "sha256-1RMC+5veDcZwwmd0O8SeOBEKsGHn9WdM+yqGwPNC6UY=";
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
