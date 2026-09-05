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
