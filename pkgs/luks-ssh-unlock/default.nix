{ lib
, stdenv
, fetchFromGitHub
, makeWrapper
, curl
, jq
, openssh
}:

stdenv.mkDerivation rec {
  pname = "luks-ssh-unlock";
  version = "e05c5f8fc807b5778e4c677f39c1c1f6300ff034";

  src = fetchFromGitHub {
    owner = "pschmitt";
    repo = "${pname}";
    rev = "${version}";
    hash = "sha256-kfInuwwfw+uvheAcpeBTYwXnm0NIXzlb+/zLvG+BAbE=";
  };

  nativeBuildInputs = [ makeWrapper ];

  installPhase = ''
    mkdir -p $out/bin
    cp $src/luks-ssh-unlock.sh $out/bin/luks-ssh-unlock
    chmod +x $out/bin/luks-ssh-unlock

    wrapProgram $out/bin/luks-ssh-unlock --prefix PATH : ${lib.makeBinPath [
      curl
      jq
      openssh
    ]}
  '';

  meta = with lib; {
    description = " Auto-unlock remote hosts via SSH and Kubernetes";
    homepage = "https://github.com/pschmitt/luks-ssh-unlock";
    license = licenses.gpl3Only;
    maintainers = with maintainers; [ pschmitt ];
    mainProgram = "luks-ssh-unlock";
    platforms = platforms.all;
  };
}
