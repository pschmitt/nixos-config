{
  lib,
  rustPlatform,
  fetchFromGitHub,
  pkg-config,
  libxkbcommon,
  stdenv,
  wayland,
}:

rustPlatform.buildRustPackage rec {
  pname = "waypoint";
  version = "unstable-2025-01-23";

  src = fetchFromGitHub {
    owner = "tadeokondrak";
    repo = pname;
    rev = "da87598171571866910a86ec69398d2bf83b814c";
    hash = "sha256-7ajLRQCX7igaad+5MxE2aOvrczsim7xJ+m0Jt1lLOrs=";
  };

  cargoHash = "sha256-PZSWoKo9QZRNWm94axra3wOExpzLu79W1wkmY88tM4E=";

  nativeBuildInputs = [
    pkg-config
  ];

  buildInputs =
    [
      libxkbcommon
    ]
    ++ lib.optionals stdenv.isLinux [
      wayland
    ];

  meta = {
    description = "Wayland clone of keynav";
    homepage = "https://github.com/tadeokondrak/waypoint";
    license = lib.licenses.mpl20;
    maintainers = with lib.maintainers; [ pschmitt ];
    mainProgram = "waypoint";
  };
}
