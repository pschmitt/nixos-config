{
  lib,
  python3,
  stdenvNoCC,
}:
stdenvNoCC.mkDerivation {
  pname = "syncthing-nautilus";
  version = "0.1.0";
  src = lib.cleanSource ./.;

  doCheck = true;
  nativeCheckInputs = [ python3 ];

  checkPhase = ''
    runHook preCheck
    PYTHONPATH=. ${python3}/bin/python -m unittest discover -s tests -v
    runHook postCheck
  '';

  installPhase = ''
    runHook preInstall
    install -d "$out/share/syncthing-nautilus" "$out/share/nautilus-python/extensions"
    install -d "$out/share/syncthing-nautilus/syncthing_nautilus"
    install -Dm644 syncthing_nautilus/*.py -t "$out/share/syncthing-nautilus/syncthing_nautilus"
    install -Dm644 syncthing_status.py "$out/share/nautilus-python/extensions/syncthing_status.py"
    runHook postInstall
  '';

  meta = {
    description = "Lightweight Syncthing sync-status emblems for Nautilus";
    homepage = "https://github.com/pschmitt/nixos-config";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
  };
}
