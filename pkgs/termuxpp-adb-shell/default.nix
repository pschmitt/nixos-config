{
  lib,
  stdenvNoCC,
  makeWrapper,
  installShellFiles,
  bash,
  zsh,
  fish,
  python3,
  android-tools,
  openssl,
}:
stdenvNoCC.mkDerivation {
  pname = "termuxpp-adb-shell";
  version = "0.3.0";
  src = ./.;
  nativeBuildInputs = [
    makeWrapper
    installShellFiles
  ];
  nativeCheckInputs = [
    python3
    bash
    zsh
    fish
  ];
  doCheck = true;
  checkPhase = ''
    runHook preCheck
    python3 -I -m unittest discover -s . -p test_termuxpp_adb_shell.py
    runHook postCheck
  '';
  installPhase = ''
    runHook preInstall
    install -Dm644 termuxpp-adb-shell.py "$out/libexec/termuxpp-adb-shell.py"
    install -Dm644 completions/termuxpp-adb-shell.bash "$out/libexec/completions/termuxpp-adb-shell.bash"
    install -Dm644 completions/termuxpp-adb-shell.zsh "$out/libexec/completions/termuxpp-adb-shell.zsh"
    install -Dm644 completions/termuxpp-adb-shell.fish "$out/libexec/completions/termuxpp-adb-shell.fish"
    installShellCompletion --cmd termuxpp-adb-shell \
      --bash completions/termuxpp-adb-shell.bash \
      --zsh completions/termuxpp-adb-shell.zsh \
      --fish completions/termuxpp-adb-shell.fish
    makeWrapper ${python3}/bin/python3 "$out/bin/termuxpp-adb-shell" \
      --add-flags "-I $out/libexec/termuxpp-adb-shell.py" \
      --prefix PATH : ${
        lib.makeBinPath [
          android-tools
          openssl
        ]
      }
    runHook postInstall
  '';
  meta = {
    description = "TermuxPP ADB shell client with run-as and fingerprint-approved mTLS transports";
    mainProgram = "termuxpp-adb-shell";
    platforms = lib.platforms.linux;
  };
}
