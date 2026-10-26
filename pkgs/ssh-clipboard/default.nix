{
  lib,
  fetchFromGitHub,
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

  patches = [
    # Treat an empty Wayland clipboard as empty instead of logging a capture
    # failure on every poll
    ./empty-wayland-clipboard.patch
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
