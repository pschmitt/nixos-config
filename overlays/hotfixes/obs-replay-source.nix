{ prev }:
{
  # obs-replay-source 1.8.1 calls the deprecated OBS button API, which fails
  # with OBS 32.2.2. Base build fails; no upstream fix is known. Reviewed
  # 2026-11-06 at Nixpkgs
  # 1d060086d60cb76a40cf37109f979d88a5bd6396. Remove when upstream updates it.
  obs-studio-plugins = prev.obs-studio-plugins // {
    obs-replay-source = prev.obs-studio-plugins.obs-replay-source.overrideAttrs (old: {
      postPatch = (old.postPatch or "") + ''
        substituteInPlace replay-source.c \
          --replace-fail \
            'obs_properties_add_button(props, "replay_button", obs_module_text("LoadReplay"), replay_button);' \
            'obs_properties_add_button2(props, "replay_button", obs_module_text("LoadReplay"), replay_button, s);'
      '';
    });
  };
}
