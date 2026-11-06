{ final, prev }:
{
  # Restore the 0.9.7-dev Python 3.14 compatibility baseline. The earlier 1.0.0
  # assessment used a nested nixpkgs pin, not this flake's top-level pin.
  # Recheck against 1d060086d60cb76a40cf37109f979d88a5bd6396 before removing.
  home-assistant-cli = prev.home-assistant-cli.overrideAttrs (oldAttrs: {
    version = "0.9.7-dev";

    src = final.fetchFromGitHub {
      owner = "home-assistant-ecosystem";
      repo = "home-assistant-cli";
      rev = "03a6edbc7b9e38d6d6260d3813e6da5e08b45a43";
      hash = "sha256-opuHn7ngSEpUdYkDYzq2QRgkZYfqhG+Uw1DbME6kxwQ=";
    };
    postPatch = (oldAttrs.postPatch or "") + ''
      substituteInPlace homeassistant_cli/remote.py \
        --replace-fail "    loop = asyncio.get_event_loop()" "" \
        --replace-fail '    result = loop.run_until_complete(fetcher())' \
          '    result = asyncio.run(fetcher())'
      substituteInPlace tests/conftest.py \
        --replace-fail 'import pkg_resources' "" \
        --replace-fail "FIXTURES_PATH = pkg_resources.resource_filename(__name__, 'fixtures/')" \
          "FIXTURES_PATH = os.path.join(os.path.dirname(__file__), 'fixtures/')"
    '';
    disabledTests = (oldAttrs.disabledTests or [ ]) ++ [ "test_defaults" ];
  });
}
