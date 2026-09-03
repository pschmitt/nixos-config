{
  lib,
  stdenvNoCC,
  fetchurl,
  autoPatchelfHook,
  stdenv,
}:

stdenvNoCC.mkDerivation rec {
  pname = "ai-usagebar";
  version = "1.10.0";

  src = fetchurl {
    url = "https://github.com/akitaonrails/ai-usagebar/releases/download/v${version}/ai-usagebar-linux-x86_64.tar.gz";
    sha256 = "ffa354e965023c492270a13fc126304fb662370ff9dbf7699751241511cd4804";
  };

  nativeBuildInputs = [ autoPatchelfHook ];
  buildInputs = [ stdenv.cc.cc.lib ];

  sourceRoot = ".";

  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin
    install -m755 ai-usagebar ai-usagebar-tui $out/bin/
    runHook postInstall
  '';

  meta = {
    description = "AI plan quota CLI (Claude, Codex, Cursor, and others), read by the Noctalia ai-usagebar plugin";
    homepage = "https://github.com/akitaonrails/ai-usagebar";
    license = lib.licenses.mit;
    platforms = [ "x86_64-linux" ];
  };
}
