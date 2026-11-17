{ pkgs }:
let
  mkSystem =
    extra:
    import ./. {
      inputs = { };
      inherit pkgs;
      modules = [
        {
          networking.hostName = "guest-test";
          user = {
            name = "guest";
            home = "/home/guest";
          };
          system.stateVersion = "1";
          environment.systemPackages = [ pkgs.hello ];
          environment.etc."nested/example.conf".text = "example=yes\n";
        }
        extra
      ];
    };
  valid = mkSystem { };
  hmFixture = pkgs.runCommand "guest-home-fixture" { } ''
    mkdir -p "$out"
    touch "$out/activate"
  '';
  integrated = mkSystem {
    home-manager.configuration.activationPackage = hmFixture;
    environment.etc."source.conf".source = pkgs.writeText "source.conf" "source=yes\n";
  };
  invalidPath = mkSystem { environment.etc."../escape".text = "bad"; };
  invalidSource = mkSystem {
    environment.etc."ambiguous" = {
      text = "bad";
      source = pkgs.writeText "other-source" "bad";
    };
  };
in
assert !(builtins.tryEval invalidPath.system).success;
assert !(builtins.tryEval invalidSource.system).success;
pkgs.runCommand "termuxpp-system-assembly-tests" { nativeBuildInputs = [ pkgs.python3 ]; } ''
  test -x ${valid.system}/sw/bin/hello
  test "$(cat ${valid.system}/etc/nested/example.conf)" = example=yes
  test ! -e ${valid.system}/home-manager
  test "$(readlink ${integrated.system}/home-manager)" = ${hmFixture}
  test "$(cat ${integrated.system}/etc/source.conf)" = source=yes
  python3 -I - ${valid.system}/manifest.json ${integrated.system}/manifest.json ${hmFixture} <<'PY'
  import json, sys
  with open(sys.argv[1]) as stream:
      data = json.load(stream)
  assert data['formatVersion'] == 1
  assert data['hostName'] == 'guest-test'
  assert data['name'] == 'guest'
  assert data['home'] == '/home/guest'
  assert data['runtime'] == 'droid-nix'
  assert data['homeManager'] is None
  assert data['activationSupported'] is False
  with open(sys.argv[2]) as stream:
      integrated = json.load(stream)
  assert integrated['homeManager'] == sys.argv[3]
  PY
  touch "$out"
''
