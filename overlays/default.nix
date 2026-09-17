{ inputs, ... }:
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
    # // (import ./netbird.nix { inherit final prev; })
    // (import ./rbw.nix { inherit inputs final prev; })
    // (import ./wireguard-tools.nix { inherit final prev; })
    // (import ./hotfixes.nix { inherit inputs final prev; })
    # // (import ./tmux.nix { inherit final prev; })
    // (import ./hyprgrass.nix { inherit inputs final prev; })
    // (import ./noctalia.nix { inherit inputs final prev; })
    // {
      # GitHub's codeload tarball for Playwright v1.63.0 changed bytes after
      # nixpkgs recorded its hash.  Keep the main package set in sync with the
      # equivalent nixpkgs-master workaround below; pytr uses this package set.
      pythonPackagesExtensions = prev.pythonPackagesExtensions ++ [
        (_pyfinal: pyprev: {
          playwright = pyprev.playwright.overridePythonAttrs (_old: {
            src = final.fetchFromGitHub {
              owner = "microsoft";
              repo = "playwright-python";
              tag = "v${pyprev.playwright.version}";
              hash = "sha256-RwIn+0EcHnStjORVFmT7gp4bGjl+qer1FgtI3+aPF2w=";
            };
          });

          # Same libmanette/WebKit autoPatchelf breakage as the
          # nixpkgs-master override below (nixpkgs' playwright-driver.browsers
          # is missing libmanette in buildInputs). This main package set's
          # pytest-playwright is pulled in transitively by paperless-ngx
          # (via hermes-agent), so it needs the same preCheck drop -- nothing
          # in preCheck's PLAYWRIGHT_BROWSERS_PATH setup is actually used
          # since doCheck is already false upstream.
          pytest-playwright = pyprev.pytest-playwright.overridePythonAttrs (_old: {
            preCheck = "";
          });
        })
      ];
    }; # Continue merging additional overlays as needed
  # When applied, the unstable nixpkgs set (declared in the flake inputs) will
  # be accessible through 'pkgs.unstable'
  unstable-packages = final: prev: {
    unstable = import inputs.nixpkgs-unstable {
      inherit (final.stdenv.hostPlatform) system;
      config.allowUnfree = true;
    };

    master = import inputs.nixpkgs-master {
      inherit (final.stdenv.hostPlatform) system;
      config.allowUnfree = true;
      overlays = [
        (mfinal: mprev: {
          # GitHub's codeload tarball for this tag changed bytes after
          # nixpkgs-master recorded its hash (a known codeload
          # re-compression quirk, not a content change) -- pulled in
          # transitively by netbox's django-polymorphic/drf-spectacular
          # test deps. Goes in via pythonPackagesExtensions (composed into
          # every python package set nixpkgs builds, unlike
          # packageOverrides, which a package's own `python3.override
          # { packageOverrides = ...; }` -- as netbox's does -- can
          # shadow) so it reaches netbox's self-referential python
          # reconstruction too. Drop once nixpkgs-master catches up.
          pythonPackagesExtensions = mprev.pythonPackagesExtensions ++ [
            (pyfinal: pyprev: {
              playwright = pyprev.playwright.overridePythonAttrs (_old: {
                src = mfinal.fetchFromGitHub {
                  owner = "microsoft";
                  repo = "playwright-python";
                  tag = "v${pyprev.playwright.version}";
                  hash = "sha256-RwIn+0EcHnStjORVFmT7gp4bGjl+qer1FgtI3+aPF2w=";
                };
              });

              # doCheck is already false upstream, but preCheck still
              # string-interpolates playwright-driver.browsers (the actual
              # WebKit/Chromium/Firefox binaries) into PLAYWRIGHT_BROWSERS_PATH,
              # which forces Nix to build them even though the check phase
              # that would use it never runs. That pulls in an unrelated,
              # currently-broken nixpkgs-master bug (WebKit's minibrowser-wpe
              # is missing libmanette for autoPatchelf). Drop preCheck instead
              # of chasing that bug -- nothing here ever gets used.
              pytest-playwright = pyprev.pytest-playwright.overridePythonAttrs (_old: {
                preCheck = "";
              });
            })
          ];
        })
      ];
    };
  };

  flakes =
    final: prev:
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

  old-packages = final: prev: {
    # https://lazamar.co.uk/nix-versions/?channel=nixpkgs-unstable&package=kubectl
    kubectl-123 = import (builtins.fetchTarball {
      url = "https://github.com/NixOS/nixpkgs/archive/611bf8f183e6360c2a215fa70dfd659943a9857f.tar.gz";
      sha256 = "sha256:1rhrajxywl1kaa3pfpadkpzv963nq2p4a2y4vjzq0wkba21inr9k";
    }) { inherit (final.stdenv.hostPlatform) system; };

    terraform-157 = import (builtins.fetchTarball {
      url = "https://github.com/NixOS/nixpkgs/archive/4ab8a3de296914f3b631121e9ce3884f1d34e1e5.tar.gz";
      sha256 = "sha256:095mc0mlag8m9n9zmln482a32nmbkr4aa319f2cswyfrln9j41cr";
    }) { inherit (final.stdenv.hostPlatform) system; };
  };
}
