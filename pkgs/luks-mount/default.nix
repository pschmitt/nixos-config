{ lib
, stdenv
, fetchFromGitHub
, makeWrapper
, yq
}:

stdenv.mkDerivation {
  pname = "luks-mount";
  version = "unstable-2024-02-05";

  src = fetchFromGitHub {
    owner = "pschmitt";
    repo = "luks-mount.sh";
    rev = "d3cd2636790a2fdcda7661a52ebbd0e87c503051";
    hash = "sha256-4jHUPfgSbA4MJS4TtNU3HRaHe1McGiJkgLk/5J8RBZ0=";
  };

  nativeBuildInputs = [ makeWrapper ];

  installPhase = ''
    mkdir -p $out/bin
    cp $src/luks-mount.sh $out/bin/luks-mount
    chmod +x $out/bin/luks-mount
    # Assuming you might need to wrap the script to include dependencies:
    wrapProgram $out/bin/luks-mount --prefix PATH : ${lib.makeBinPath [ yq ]}
  '';

  meta = with lib; {
    description = "Quick and dirty mount script for removable LUKS devices using a config file";
    homepage = "https://github.com/pschmitt/luks-mount.sh";
    license = licenses.gpl3Only;
    maintainers = with maintainers; [ pschmitt ];
    mainProgram = "luks-mount";
    platforms = platforms.all;
  };
}
