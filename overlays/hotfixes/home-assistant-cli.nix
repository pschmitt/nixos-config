{ prev }:
{
  # Python 3.14 no longer creates an implicit event loop, so wsapi() fails with
  # "There is no current event loop in thread 'MainThread'" (hass-cli raw ws,
  # service call via websocket). Observed 2026-11-11 with home-assistant-cli
  # 1.0.0. No upstream fix is known; remove once remote.py stops calling
  # asyncio.get_event_loop().
  home-assistant-cli = prev.home-assistant-cli.overrideAttrs (old: {
    postPatch = (old.postPatch or "") + ''
      substituteInPlace homeassistant_cli/remote.py \
        --replace-fail 'loop = asyncio.get_event_loop()' 'loop = asyncio.new_event_loop()'
    '';
  });
}
