{ inputs, ... }:
let
  # GitHub's codeload tarball for Playwright v1.63.0 changed bytes after
  # nixpkgs recorded its hash (a known codeload re-compression quirk, not a
  # content change).
  #
  # pytest-playwright: doCheck is already false upstream, but preCheck still
  # string-interpolates playwright-driver.browsers into
  # PLAYWRIGHT_BROWSERS_PATH, which forces Nix to build the browsers even
  # though the check phase never runs. That pulls in WebKit's minibrowser-wpe,
  # whose autoPatchelf currently fails on a missing libmanette. Pulled in via
  # paperless-ngx (hermes-agent) and netbox's test deps.
  #
  # Applied through pythonPackagesExtensions (composed into every python
  # package set nixpkgs builds, unlike packageOverrides, which a package's own
  # `python3.override { packageOverrides = ...; }` -- as netbox's does -- can
  # shadow).
  playwrightFixes = fetchFromGitHub: _pyfinal: pyprev: {
    playwright = pyprev.playwright.overridePythonAttrs (_old: {
      src = fetchFromGitHub {
        owner = "microsoft";
        repo = "playwright-python";
        tag = "v${pyprev.playwright.version}";
        hash = "sha256-RwIn+0EcHnStjORVFmT7gp4bGjl+qer1FgtI3+aPF2w=";
      };
    });

    pytest-playwright = pyprev.pytest-playwright.overridePythonAttrs (_old: {
      preCheck = "";
    });
  };
in
{
  # This one brings our custom packages from the 'pkgs' directory
  additions =
    final: _prev:
    let
      customPackages = import ../pkgs {
        pkgs = final;
        inherit inputs;
      };
    in
    customPackages
    // {
      # Include luks-ssh-unlock from the flake
      luks-ssh-unlock = inputs.luks-ssh-unlock.packages.${final.stdenv.hostPlatform.system}.default;
    };

  # This one contains whatever you want to overlay
  # You can change versions, add patches, set compilation flags, anything really.
  # https://nixos.wiki/wiki/Overlays
  modifications =
    final: prev:
    (import ./hass-cli.nix { inherit final prev; })
    // (import ./go-task.nix { inherit final prev; })
    // (import ./rbw.nix { inherit inputs final prev; })
    // (import ./wireguard-tools.nix { inherit final prev; })
    // (import ./hotfixes.nix { inherit inputs final prev; })
    // (import ./noctalia.nix { inherit inputs final prev; })
    // (import ./zsh-completions.nix { inherit inputs final prev; })
    // {
      # Lan Mouse normally assigns its Wayland virtual keyboard the local
      # compositor's keymap. Allow a service-specific map so remote input can
      # use the peer's layout without changing physical keyboards.
      lan-mouse =
        inputs.lan-mouse.packages.${final.stdenv.hostPlatform.system}.default.overrideAttrs
          (_old: {
            src = final.applyPatches {
              name = "lan-mouse-patched";
              src = inputs.lan-mouse;
              patches = [
                ../pkgs/local/lan-mouse/0001-env-keymap.patch
                ../pkgs/local/lan-mouse/0002-input-state.patch
              ];
            };
          });

      # The SAML configuration checks exposed by enabling pysaml2 also need
      # pytz, which the Nixpkgs Matrix Synapse package omits from its SAML extra.
      matrix-synapse-unwrapped = prev.matrix-synapse-unwrapped.overridePythonAttrs (old: {
        nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ final.python3Packages.pytz ];
        propagatedBuildInputs = (old.propagatedBuildInputs or [ ]) ++ [ final.python3Packages.pytz ];
      });

      pythonPackagesExtensions = prev.pythonPackagesExtensions ++ [
        (playwrightFixes final.fetchFromGitHub)
        (_pyfinal: pyprev: {
          # The 8 kHz mp3 encoder-vs-ffmpeg-CLI comparison misses its 1e-3
          # tolerance (~1.7e-3) with the current ffmpeg. Pulled in by
          # paperless-ngx via sentence-transformers -> torchaudio.
          torchcodec = pyprev.torchcodec.overridePythonAttrs (old: {
            disabledTests = (old.disabledTests or [ ]) ++ [ "test_audio_against_cli" ];
          });
        })
        (_pyfinal: pyprev: {
          # Pygments changed HTML escaping for quoted docstrings, making these
          # diff-cover snapshot tests fail while its runtime behavior remains
          # unaffected. Needed by sqlfluff in the ge2 system closure.
          diff-cover = pyprev.diff-cover.overridePythonAttrs (old: {
            disabledTests = (old.disabledTests or [ ]) ++ [
              "test_added_file_pycodestyle_html"
              "test_all_reports"
              "test_added_file_pyflakes_html"
              "test_added_file_pylint_html"
              "test_fail_under_html"
              "test_fail_under_pass_html"
            ];
          });
        })
        (_pyfinal: pyprev: {
          # jwcrypto now enforces RFC 7518's 256-bit minimum for HS256 keys;
          # these websockify tests use a 72-bit fixture key.
          websockify = pyprev.websockify.overridePythonAttrs (old: {
            disabledTests = (old.disabledTests or [ ]) ++ [
              "test_symmetric_jws_token_plugin"
              "test_symmetric_jws_token_plugin_with_illigal_key_exception"
            ];
          });
        })
        (_pyfinal: pyprev: {
          # xmlschema 4 applies its sandbox to validated documents as well as
          # schemas. pysaml2 7.5.4 passes file paths directly, so its schema
          # validation tests fail when the fixtures are outside the schema
          # directory. Loading them as XMLResource restores the xmlschema 2/3
          # behavior; this patch is upstream PR #1044.
          pysaml2 = pyprev.pysaml2.overridePythonAttrs (old: {
            patches = (old.patches or [ ]) ++ [ ./patches/pysaml2-xmlschema4.patch ];
          });
        })
        (_pyfinal: pyprev: {
          # xmlschema 4.3.1 introspects class attributes while clearing cached
          # properties. zope.interface's __provides__ descriptor raises
          # AttributeError on class access; skip descriptors that do so.
          # Matrix Synapse imports pysaml2 in its test suite and exposes this.
          xmlschema = pyprev.xmlschema.overridePythonAttrs (old: {
            patches = (old.patches or [ ]) ++ [ ./patches/xmlschema-zope-interface.patch ];
          });

        })
      ];
    }; # Continue merging additional overlays as needed

  # nixpkgs master, accessible through 'pkgs.master'
  master-packages = final: _prev: {
    stable = import inputs.nixpkgs-stable {
      inherit (final.stdenv.hostPlatform) system;
      config.allowUnfree = true;
    };

    master = import inputs.nixpkgs-master {
      inherit (final.stdenv.hostPlatform) system;
      config = {
        allowUnfree = true;
        allowBroken = true;
      };
      overlays = [
        (mfinal: mprev: {
          pythonPackagesExtensions = mprev.pythonPackagesExtensions ++ [
            (playwrightFixes mfinal.fetchFromGitHub)
          ];
        })
      ];
    };
  };

  flakes =
    final: _prev:
    let
      libMozilla = import (inputs.firefox-addons + "/../../lib/mozilla.nix") { inherit (final) lib; };
      buildMozillaXpiAddon = libMozilla.mkBuildMozillaXpiAddon { inherit (final) fetchurl stdenv; };
    in
    {
      firefox-addons = import inputs.firefox-addons {
        inherit buildMozillaXpiAddon;
        inherit (final) fetchurl lib stdenv;
      };
    };

  llm-agents = inputs.llm-agents.overlays.shared-nixpkgs;

  old-packages = final: _prev: {
    kubectl-123 = import inputs.nixpkgs-kubectl-123 { inherit (final.stdenv.hostPlatform) system; };
    terraform-157 = import inputs.nixpkgs-terraform-157 { inherit (final.stdenv.hostPlatform) system; };
  };
}
