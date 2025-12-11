{
  lib,
  rustPlatform,
  fetchFromGitHub,
  pkg-config,
  libxkbcommon,
  stdenv,
  wayland,
  nix-update-script,
}:

rustPlatform.buildRustPackage rec {
  pname = "waypoint";
  version = "unstable-2025-06-10";

  src = fetchFromGitHub {
    owner = "tadeokondrak";
    repo = pname;
    rev = "bfd3a4ddf75b0be933ea8954f7db0fdb6fd22fab";
    hash = "sha256-WUsJlZAmIhKMNuQI74fyiUCLvQ321bz2vkSHJ8YVLbg=";
  };

  cargoHash = "sha256-U2xHFII0FMG9Zc+2W3JguBIXIgtfWIHWsUUDxnjoF5U=";

  nativeBuildInputs = [
    pkg-config
  ];

  buildInputs = [
    libxkbcommon
  ]
  ++ lib.optionals stdenv.isLinux [
    wayland
  ];

  passthru.updateScript = nix-update-script {
    extraArgs = [
      "--flake"
      "--version"
      "branch"
    ];
  };

  meta = {
    description = "Wayland clone of keynav";
    homepage = "https://github.com/tadeokondrak/waypoint";
    license = lib.licenses.mpl20;
    maintainers = with lib.maintainers; [ pschmitt ];
    mainProgram = "waypoint";
  };
}
