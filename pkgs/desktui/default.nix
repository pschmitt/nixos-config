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
  version = "0.4.0";

  src = fetchFromGitHub {
    owner = "mishushakov";
    repo = "desktui";
    tag = "v${finalAttrs.version}";
    hash = "sha256-cfAdwDh/2RhlCAV21OfYQGa/YVP3XAZZs61Nm3G4bsg=";
  };

  cargoHash = "sha256-TUul0KS4Vth+su6mlipwStMmoS8iOimdbW0Fb4ipqKk=";

  patches = [ ./tmux-passthrough.patch ];

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
    homepage = "https://github.com/mishushakov/desktui";
    license = lib.licenses.mit;
    maintainers = [ lib.maintainers.pschmitt ];
    mainProgram = "desktui";
    platforms = lib.platforms.unix;
  };
})
