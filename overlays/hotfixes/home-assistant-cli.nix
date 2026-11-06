{ prev }:
{
  # remote.py asks asyncio for a current loop in a context that has none on
  # Python 3.14. Upstream 1.0.0 passes checks unchanged. Reviewed 2026-11-06
  # at Nixpkgs b1b875982b17dabde9b4a37f3e229e74913e6db3; remove when upstream
  # uses asyncio.run().
  home-assistant-cli = prev.home-assistant-cli.overrideAttrs (oldAttrs: {
    postPatch = (oldAttrs.postPatch or "") + ''
      substituteInPlace homeassistant_cli/remote.py \
        --replace-fail "    loop = asyncio.get_event_loop()" "" \
        --replace-fail '    result = loop.run_until_complete(fetcher())' \
          '    result = asyncio.run(fetcher())'
    '';
  });
}
