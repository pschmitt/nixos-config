# Worker tests for the sops-nix support of both guest layers.
#
#   nix build --impure --expr \
#     'import ./profiles/specializations/termuxpp/sops-tests.nix { inputs = (builtins.getFlake (toString ./.)).inputs; }'
#
# Behavior is architecture independent, so the scripts are run natively on
# x86_64 (no emulation); the real guest configurations are only evaluated.
# The age key and the sops file are generated inside the build from synthetic
# values; nothing secret is committed and no value is ever printed.
{
  inputs,
  system ? "x86_64-linux",
}:
let
  pkgs = inputs.nixpkgs.legacyPackages.${system};
  inherit (pkgs) lib;

  # The sandbox build directory; key and homes must be outside the Nix store.
  root = "/build/sops-test";
  keyFile = "${root}/key/key.txt";
  home = "${root}/home";
  runtime = "${root}/run";

  fixture =
    pkgs.runCommand "sops-test-fixture"
      {
        nativeBuildInputs = [
          pkgs.age
          pkgs.sops
        ];
      }
      ''
        mkdir -p "$out"
        age-keygen -o "$out/key.txt" 2>/dev/null
        public=$(age-keygen -y "$out/key.txt")
        printf '%s\n' \
          'system_token: synthetic-system-value' \
          'hm_token: synthetic-hm-value' \
          'shared: synthetic-shared-value' > plain.yaml
        sops --encrypt --age "$public" --input-type yaml --output-type yaml plain.yaml > "$out/secrets.yaml"
        age-keygen -o "$out/wrong-key.txt" 2>/dev/null
      '';
  sopsFile = "${fixture}/secrets.yaml";

  systemSecrets = {
    system_token = { };
    shared = {
      path = "%r/system-custom/shared";
      mode = "0440";
    };
  };
  mkSystem =
    secrets: templates:
    import ../../../modules/nixpp/eval.nix {
      inherit inputs pkgs;
      modules = [
        (
          { config, ... }:
          {
            networking.hostName = "sops-test";
            user = {
              name = "guest";
              home = "/home/guest";
            };
            system.stateVersion = "1";
            nixpp.sops.runtimeDir = "${root}/run-fallback";
            sops = {
              defaultSecretsMountPoint = "%r/termuxpp-system/secrets.d";
              defaultSymlinkPath = "%r/termuxpp-system/sops-nix/secrets";
              defaultSopsFile = sopsFile;
              age.keyFile = keyFile;
              inherit secrets;
              templates = lib.mapAttrs (_: content: {
                content = content config.sops.placeholder;
              }) templates;
            };
          }
        )
      ];
    };
  systemFull = mkSystem systemSecrets {
    "sys.conf" = placeholder: "value=${placeholder.system_token}\n";
  };
  systemFewer = mkSystem { inherit (systemSecrets) system_token; } { };
  systemNone = mkSystem { } { };

  mkHome =
    secrets: templates:
    inputs.home-manager.lib.homeManagerConfiguration {
      inherit pkgs;
      extraSpecialArgs = { inherit inputs; };
      modules = [
        ../../../modules/home-manager/termuxpp/sops.nix
        (
          { config, ... }:
          {
            home = {
              username = "guest";
              homeDirectory = home;
              stateVersion = "26.05";
            };
            sops = {
              defaultSopsFile = sopsFile;
              age.keyFile = keyFile;
              inherit secrets;
              templates = lib.mapAttrs (_: content: {
                content = content config.sops.placeholder;
              }) templates;
            };
          }
        )
      ];
    };
  homeSecrets = {
    hm_token = { };
    hm_custom = {
      key = "shared";
      path = "${home}/custom-secret";
    };
  };
  homeFull = mkHome homeSecrets { "hm.conf" = placeholder: "value=${placeholder.hm_token}\n"; };
  homeNone = mkHome { } { };

  # The real guest configurations: evaluated only, never built here.
  guestHomes = import ./homes.nix { inherit inputs; };
  guestSystems = import ./systems.nix { inherit inputs; };
  # Verify the configured system and Home Manager locations for both phones.
  guestChecks = lib.mapAttrsToList (
    hostname: guest:
    let
      systemConfig = guestSystems.${hostname}.config;
    in
    assert guest.config.home.activation ? sops-nix;
    assert guest.config.sops.defaultSecretsMountPoint == "%r/secrets.d";
    assert systemConfig.sops.defaultSecretsMountPoint == "/run/secrets.d";
    assert systemConfig.sops.defaultSymlinkPath == "/run/secrets";
    assert systemConfig.system.build.secretsActivation != null;
    true
  ) guestHomes;

  # Evaluation of a system configuration that must be rejected.
  rejected =
    sops:
    !(builtins.tryEval
      (import ../../../modules/nixpp/eval.nix {
        inherit inputs pkgs;
        modules = [
          {
            networking.hostName = "sops-test";
            user = {
              name = "guest";
              home = "/home/guest";
            };
            system.stateVersion = "1";
            sops = {
              defaultSopsFile = sopsFile;
            }
            // sops;
          }
        ];
      }).system
    ).success;

  assertions =
    assert
      homeFull.config.home.activation.sops-nix.data == "run ${homeFull.config.nixpp.sops.activation}\n";
    assert !(lib.hasInfix "systemctl" homeFull.config.home.activation.sops-nix.data);
    assert !homeFull.config.xdg.configFile."systemd/user/sops-nix.service".enable;
    assert builtins.elem "linkGeneration" homeFull.config.home.activation.sops-nix.after;
    assert builtins.elem "androidAcceptance" homeFull.config.home.activation.sops-nix.before;
    # Without secrets upstream installs nothing: no entry, no hook.
    assert !(homeNone.config.home.activation ? sops-nix);
    assert homeNone.config.nixpp.sops.activation == null;
    assert systemNone.config.system.build.secretsActivation == null;
    assert
      systemFull.config.sops.secrets.system_token.path
      == "%r/termuxpp-system/sops-nix/secrets/system_token";
    assert
      systemFull.config.sops.templates."sys.conf".path
      == "%r/termuxpp-system/sops-nix/secrets/rendered/sys.conf";
    assert
      homeFull.config.sops.defaultSecretsMountPoint != systemFull.config.sops.defaultSecretsMountPoint;
    assert homeFull.config.sops.defaultSymlinkPath != systemFull.config.sops.defaultSymlinkPath;
    # Upstream's assertions still apply: no key source is rejected, and so is
    # an inconsistent gnupg configuration.
    assert rejected { secrets.x = { }; };
    assert rejected {
      age.keyFile = keyFile;
      gnupg.home = "/nonexistent";
      gnupg.sshKeyPaths = [ "/nonexistent" ];
      secrets.x = { };
    };
    assert builtins.all (item: item) guestChecks;
    true;

  hmActivate = homeFull.config.nixpp.sops.activation;
  jq = "${pkgs.jq}/bin/jq";
  sysFull = "${systemFull.config.system.build.secretsActivation}/bin/activate-secrets";
  sysFewer = "${systemFewer.config.system.build.secretsActivation}/bin/activate-secrets";
in
assert assertions;
pkgs.runCommand "full-nix-sops-tests" { } ''
  set -eu
  fail() { echo "FAIL: $*" >&2; exit 1; }
  # Values are synthetic, but never print them anyway.
  expect() { [ "$(cat "$1")" = "$2" ] || fail "unexpected content: $1"; }
  expect_mode() { [ "$(stat -L -c %a "$1")" = "$2" ] || fail "unexpected mode $(stat -L -c %a "$1" 2>&1): $1"; }
  absent() { [ ! -e "$1" ] && [ ! -L "$1" ] || fail "should not exist: $1"; }
  generations() { find "$1" -mindepth 1 -maxdepth 1 -regex '.*/[0-9]+' | wc -l; }

  [ "$NIX_BUILD_TOP" = /build ] || fail "expected the Linux sandbox build directory"
  install -D -m 0600 ${fixture}/key.txt ${keyFile}
  mkdir -p ${home} ${runtime}
  export HOME=${home}
  export XDG_RUNTIME_DIR=${runtime}
  sys=${runtime}/termuxpp-system/sops-nix/secrets
  sysmount=${runtime}/termuxpp-system/secrets.d
  hm=${runtime}

  echo "== no systemd involved"
  for script in ${hmActivate} ${sysFull} ${sysFewer}; do
    ! grep -q systemctl "$script" || fail "systemctl in $script"
  done
  test -x ${systemFull.system}/bin/activate-secrets
  [ "$(readlink ${systemFull.system}/bin/activate-secrets)" = ${sysFull} ]

  echo "== the built manifest names the exact hook"
  [ "$(${jq} -r .systemSecrets ${systemFull.system}/manifest.json)" = "$(readlink ${systemFull.system}/bin/activate-secrets)" ] \
    || fail "manifest systemSecrets is not the toplevel hook"
  [ "$(${jq} -r .systemSecrets ${systemFull.system}/manifest.json)" = ${sysFull} ] \
    || fail "manifest systemSecrets differs from the configured activation"
  [ "$(${jq} -r .formatVersion ${systemFull.system}/manifest.json)" = 1 ] \
    || fail "manifest lost its regular fields"
  ${jq} -e '.systemSecrets | startswith("/nix/store/") and endswith("/bin/activate-secrets")' ${systemFull.system}/manifest.json > /dev/null

  echo "== without secrets there is no hook"
  test ! -e ${systemNone.system}/bin/activate-secrets
  ${jq} -e 'has("systemSecrets") | not' ${systemNone.system}/manifest.json > /dev/null

  echo "== runtimeDir fallback and system install, templates included"
  env -u XDG_RUNTIME_DIR ${sysFull}
  fallback=${root}/run-fallback/termuxpp-system/sops-nix/secrets
  expect "$fallback/system_token" synthetic-system-value
  expect ${root}/run-fallback/system-custom/shared synthetic-shared-value
  expect "$fallback/rendered/sys.conf" "value=synthetic-system-value"
  expect_mode "$fallback/system_token" 400
  expect_mode "$fallback/shared" 440

  echo "== a different runtime dir is a different location; the earlier one is left alone"
  ${sysFull}
  expect "$sys/system_token" synthetic-system-value
  expect "$sys/rendered/sys.conf" "value=synthetic-system-value"
  expect ${runtime}/system-custom/shared synthetic-shared-value
  expect "$fallback/system_token" synthetic-system-value
  expect ${root}/run-fallback/system-custom/shared synthetic-shared-value

  echo "== running again keeps exactly one generation"
  ${sysFull}
  [ "$(generations "$sysmount")" = 1 ] || fail "old generation kept"
  expect "$sys/system_token" synthetic-system-value

  echo "== home manager install, separate namespace"
  ${hmActivate}
  expect ${home}/.config/sops-nix/secrets/hm_token synthetic-hm-value
  expect ${home}/custom-secret synthetic-shared-value
  expect ${home}/.config/sops-nix/secrets/rendered/hm.conf "value=synthetic-hm-value"
  absent ${home}/.config/sops-nix/secrets/system_token
  absent "$sys/hm_token"
  [ -d "$hm/secrets.d" ] && [ -d "$sysmount" ]
  [ "$(readlink ${home}/.config/sops-nix/secrets)" != "$(readlink "$sys")" ]

  echo "== failure propagates and keeps what is installed"
  install -m 0600 ${fixture}/wrong-key.txt ${keyFile}
  if ${sysFull}; then fail "system activation succeeded with the wrong key"; fi
  if ${hmActivate}; then fail "home activation succeeded with the wrong key"; fi
  rm -f ${keyFile}
  if ${sysFull}; then fail "system activation succeeded without a key"; fi
  if ${hmActivate}; then fail "home activation succeeded without a key"; fi
  install -m 0600 ${fixture}/key.txt ${keyFile}
  expect "$sys/system_token" synthetic-system-value
  expect ${home}/.config/sops-nix/secrets/hm_token synthetic-hm-value

  echo "== a secret that is no longer configured disappears (upstream behavior)"
  ${sysFewer}
  expect "$sys/system_token" synthetic-system-value
  absent "$sys/shared"
  absent "$sys/rendered/sys.conf"
  [ "$(generations "$sysmount")" = 1 ] || fail "old generation kept"
  # Upstream leaves the symlink of a custom path behind; it dangles.
  [ -L ${runtime}/system-custom/shared ] && [ ! -e ${runtime}/system-custom/shared ] \
    || fail "custom path of a removed secret should dangle"
  expect ${home}/.config/sops-nix/secrets/hm_token synthetic-hm-value

  echo "== removing every secret runs nothing and keeps what was installed (upstream baseline)"
  # No hook and no activation entry exist, so there is nothing to run: the data
  # of the previous generation stays until removed by hand, in both layers.
  expect "$sys/system_token" synthetic-system-value
  expect ${home}/.config/sops-nix/secrets/hm_token synthetic-hm-value
  expect ${home}/custom-secret synthetic-shared-value

  touch "$out"
''
