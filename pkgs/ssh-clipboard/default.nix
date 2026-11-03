{
  lib,
  fetchFromGitHub,
  nix-update-script,
  pkg-config,
  rustPlatform,
  wayland,
  xorg-server,
}:

rustPlatform.buildRustPackage (finalAttrs: {
  pname = "ssh-clipboard";
  version = "0.2.18";

  src = fetchFromGitHub {
    owner = "standardagents";
    repo = "ssh-clipboard";
    rev = "v${finalAttrs.version}";
    hash = "sha256-CmbDKM84U+IOP5JlGEdYNBjoMvVkY37GF+tk8ZDNogc=";
  };

  cargoHash = "sha256-LFyW5do7IZCrBU7KJmO2Mqb+5+BcUAEjVBfoheDCYn0=";

  # Upstream also pushes non-release tags (sa-issues-claim/N) that nix-update
  # would otherwise pick as the latest version
  passthru.updateScript = nix-update-script {
    extraArgs = [
      "--flake"
      "--version-regex"
      "^v(\\d+\\.\\d+\\.\\d+)$"
    ];
  };

  patches = [
    # Treat an empty Wayland clipboard as empty instead of logging a capture
    # failure on every poll
    ./empty-wayland-clipboard.patch
  ];

  checkFlags = [
    # Spawns the real service, which the build sandbox forbids (EACCES)
    "--skip=real_container_service_start_stop_restart_and_ssh_revival"
    # Drives a GTK client through python3, which is not in the sandbox
    "--skip=headless_x11_round_trip"
  ];

  nativeBuildInputs = [ pkg-config ];
  nativeCheckInputs = [ xorg-server ];
  buildInputs = [ wayland ];

  meta = {
    description = "Native encrypted clipboard synchronization over SSH";
    homepage = "https://github.com/standardagents/ssh-clipboard";
    license = lib.licenses.mit;
    maintainers = with lib.maintainers; [ pschmitt ];
    mainProgram = "ssh-clipboard";
  };
})
