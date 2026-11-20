{ pkgs, inputs }:
let
  nixppSrc = inputs.termuxpp.lib.nixpp.src;
  mkSystem =
    extra:
    import ./eval.nix {
      inherit inputs pkgs;
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
  runtimeManifest = (pkgs.formats.json { }).generate "runtime-test.json" {
    schema = 1;
    system = "aarch64-linux";
    pageSize = 4096;
  };
  hmFixture = pkgs.runCommand "guest-home-fixture" { } ''
    mkdir -p "$out"
    touch "$out/activate"
  '';
  integrated = mkSystem {
    home-manager.configuration.activationPackage = hmFixture;
    environment.etc."source.conf".source = pkgs.writeText "source.conf" "source=yes\n";
    services.fixture = {
      command = [ "${pkgs.hello}/bin/hello" ];
      environment.FIXTURE = "yes";
    };
  };
  invalidPath = mkSystem { environment.etc."../escape".text = "bad"; };
  invalidSource = mkSystem {
    environment.etc."ambiguous" = {
      text = "bad";
      source = pkgs.writeText "other-source" "bad";
    };
  };
  invalidServiceName = mkSystem {
    services."../unsafe".command = [ "${pkgs.hello}/bin/hello" ];
  };
in
assert !(builtins.tryEval invalidPath.system).success;
assert !(builtins.tryEval invalidSource.system).success;
assert !(builtins.tryEval invalidServiceName.system).success;
pkgs.runCommand "termuxpp-system-assembly-tests" { nativeBuildInputs = [ pkgs.python3 ]; } ''
  test -x ${valid.system}/sw/bin/hello
  ${valid.system}/sw/bin/svc --help >/dev/null
  ${valid.system}/sw/bin/nixpp --help
  python3 -I ${nixppSrc}/tests/test_nixpp_cli.py ${valid.system}/sw/bin/nixpp
  cp ${nixppSrc}/tests/prepare-session.py prepare-session.py
  cp ${nixppSrc}/tests/test_prepare_session.py test_prepare_session.py
  python3 -I test_prepare_session.py
  bash ${nixppSrc}/tests/test-start-transitions.sh ${valid.system}/sw/bin/nixpp \
    ${nixppSrc}/source/src/assets/start-system-control.sh
  python3 -I ${nixppSrc}/tests/test_nixpp_parity.py ${nixppSrc}/tests/prepare-session.py \
    ${valid.system}/sw/bin/nixpp ${valid.system} ${integrated.system}
  mkdir -p runtime/root/etc
  cp ${runtimeManifest} runtime/session.json
  printf 'guest:x:123:456:Guest:/home/guest:/bin/sh\n' > runtime/root/etc/passwd
  printf 'guest:x:456:\n' > runtime/root/etc/group
  ${valid.system}/sw/bin/nixpp prepare --runtime "$PWD/runtime" ${valid.system}
  candidate="$PWD/runtime/system-candidates/$(basename ${valid.system})"
  test -f "$candidate/session"
  test "$(cat "$candidate/etc/nested/example.conf")" = example=yes
  test "$(readlink "runtime/root/nix/var/nix/gcroots/termuxpp-system-candidates/$(basename ${valid.system})")" = ${valid.system}
  test ! -e runtime/current-system
  test "$(cat ${valid.system}/etc/nested/example.conf)" = example=yes
  test ! -e ${valid.system}/home-manager
  test "$(readlink ${integrated.system}/home-manager)" = ${hmFixture}
  test "$(cat ${integrated.system}/etc/source.conf)" = source=yes
  test -x ${integrated.system}/sw/bin/svc
  python3 -I - ${integrated.system}/etc/nixpp/services.json <<'PY'
  import json, sys
  with open(sys.argv[1]) as stream:
      services = json.load(stream)
  assert services['fixture']['enabled'] is True
  assert services['fixture']['directory'].startswith('/nix/store/')
  PY
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
  assert integrated['activationSupported'] is True
  PY
  touch "$out"
''
