{
  lib,
  stdenvNoCC,
  makeWrapper,
  python3,
  android-tools,
  openssl,
}:
stdenvNoCC.mkDerivation {
  pname = "termuxpp-adb-shell";
  version = "0.1.0";
  src = ./.;
  nativeBuildInputs = [ makeWrapper ];
  nativeCheckInputs = [ python3 ];
  doCheck = true;
  checkPhase = ''
    runHook preCheck
    python3 -I -m unittest discover -s . -p test_termuxpp_adb_shell.py
    runHook postCheck
  '';
  installPhase = ''
    runHook preInstall
    install -Dm644 termuxpp-adb-shell.py "$out/libexec/termuxpp-adb-shell.py"
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
    description = "Opt-in, fingerprint-approved mTLS shell client for TermuxPP over ADB";
    mainProgram = "termuxpp-adb-shell";
    platforms = lib.platforms.linux;
  };
}
