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
  version = "0.2.11";

  src = fetchFromGitHub {
    owner = "standardagents";
    repo = "ssh-clipboard";
    rev = "v${finalAttrs.version}";
    hash = "sha256-iXfEk9oir4OlKWGUZAH/czGn+A1kO/1+v3rOaEKwLxM=";
  };

  cargoHash = "sha256-Oq5Wbs62+Zolp7ZpQb0LhWIdQGbQE1IWGNZuETHVRM4=";

  patches = [
    # Treat an empty Wayland clipboard as empty instead of logging a capture
    # failure on every poll
    ./empty-wayland-clipboard.patch
  ];

  # clipboard-rs 0.3.5 serves X11 selections in one ChangeProperty: payloads
  # above the maximum request length fail and end its serving thread while it
  # keeps owning the selection, so every reader hangs. Add INCR transfers,
  # keep the thread alive on errors and make the read timeout an inactivity
  # timeout so large INCR reads can finish.
  postPatch = ''
    clipboardRs="$NIX_BUILD_TOP/${finalAttrs.cargoDeps.name}/source-registry-0/clipboard-rs-0.3.5"
    chmod -R u+w "$clipboardRs"
    patch -d "$clipboardRs" -p1 < ${./clipboard-rs-x11-incr.patch}
  '';

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
