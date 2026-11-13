{
  lib,
  makeWrapper,
  python3,
  runCommand,
}:

let
  python = python3.withPackages (ps: [ ps.websockets ]);
in
runCommand "openstack-console-tui-1.0.0"
  {
    nativeBuildInputs = [ makeWrapper ];
    passthru.pythonEnv = python;
    passthru.tests.bridge = runCommand "openstack-console-tui-tests" { } ''
      ${lib.getExe python} -I ${./.}/test_tui.py
      touch "$out"
    '';
    meta = {
      description = "Private loopback bridge from OpenStack noVNC to terminal VNC viewers";
      mainProgram = "openstack-console-tui";
      platforms = lib.platforms.unix;
    };
  }
  ''
    install -Dm644 ${./tui.py} "$out/share/openstack-console-tui/tui.py"
    makeWrapper ${lib.getExe python} "$out/bin/openstack-console-tui" \
      --add-flags "-I $out/share/openstack-console-tui/tui.py"
  ''
