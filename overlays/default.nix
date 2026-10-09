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
    # // (import ./netbird.nix { inherit final prev; })
    // (import ./rbw.nix { inherit inputs final prev; })
    // (import ./wireguard-tools.nix { inherit final prev; })
    // (import ./hotfixes.nix { inherit inputs final prev; })
    # // (import ./tmux.nix { inherit final prev; })
    // (import ./noctalia.nix { inherit inputs final prev; })
    // (import ./zsh-completions.nix { inherit inputs final prev; })
    // {
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
      ];
    }; # Continue merging additional overlays as needed

  # nixpkgs master, accessible through 'pkgs.master'
  master-packages = final: _prev: {
    master = import inputs.nixpkgs-master {
      inherit (final.stdenv.hostPlatform) system;
      config.allowUnfree = true;
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
