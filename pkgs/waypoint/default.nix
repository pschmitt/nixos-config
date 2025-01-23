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
  version = "unstable-2024-04-17";

  src = fetchFromGitHub {
    owner = "tadeokondrak";
    repo = pname;
    rev = "702657a6c18688fed97e498a9c95771b073835cc";
    hash = "sha256-ZRddQzSz++MlbbFBt5b1uZeOsOijdBtd9RfQeeTbQA4=";
  };

  cargoHash = "sha256-7r0x/GzYPht4LN1DH1a+/grVQk6hpKzxfundSUQD4LE=";

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
