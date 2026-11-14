{
  lib,
  rustPlatform,
  fetchFromGitHub,
  bash,
  ncurses,
  python3,
  runCommand,
  tmux,
}:

rustPlatform.buildRustPackage (finalAttrs: {
  pname = "desktui";
  version = "0.4.0-unstable-2026-11-14";

  # Our fork: tmux passthrough, and terminal replies never typed into the
  # remote desktop.
  src = fetchFromGitHub {
    owner = "pschmitt";
    repo = "desktui";
    rev = "147b352ec43953342236cb6aabf08b61384932b0";
    hash = "sha256-VUHUS5JmeWRLwiEGgYZH255dvMwtmojGMIxvEuQXxVY=";
  };

  cargoHash = "sha256-cFqVWPNiCuKqUOuAe+z4+FUskHhKQxcHoxwSXsQRmQY=";

  passthru.tests.tmux =
    runCommand "desktui-tmux-test"
      {
        nativeBuildInputs = [
          python3
          tmux
        ];
        SHELL = lib.getExe bash;
        TERMINFO_DIRS = "${ncurses}/share/terminfo";
      }
      ''
        python3 -I ${./tests/tmux.py} ${lib.getExe finalAttrs.finalPackage}
        touch "$out"
      '';

  meta = {
    description = "VNC client that renders remote desktops using terminal graphics";
    homepage = "https://github.com/pschmitt/desktui";
    license = lib.licenses.mit;
    maintainers = [ lib.maintainers.pschmitt ];
    mainProgram = "desktui";
    platforms = lib.platforms.unix;
  };
})
