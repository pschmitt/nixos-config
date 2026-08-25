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
  version = "0.2.9";

  src = fetchFromGitHub {
    owner = "standardagents";
    repo = "ssh-clipboard";
    rev = "v${finalAttrs.version}";
    hash = "sha256-dWFeYRvBwjz6ShLVVRhWSUBH1aMuvgHCmF72qPQ6cyI=";
  };

  cargoHash = "sha256-0cIVoq3Fpmi51uergWkWVSauJl4aFHReo7fiVtfoTkY=";

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
