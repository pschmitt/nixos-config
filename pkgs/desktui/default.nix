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
  version = "0.4.0-unstable-2026-07-26";

  # Our fork: tmux passthrough, and terminal replies never typed into the
  # remote desktop.
  src = fetchFromGitHub {
    owner = "pschmitt";
    repo = "desktui";
    rev = "29b4d26a6d240494041a240f5069175a4c0eaa42";
    hash = "sha256-2SUOeq7uZdDPISPjOBjlKXheAqER9m0QcPOuP7q5MU0=";
  };

  cargoHash = "sha256-TUul0KS4Vth+su6mlipwStMmoS8iOimdbW0Fb4ipqKk=";

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
