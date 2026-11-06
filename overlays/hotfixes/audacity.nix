{ prev }:
{
  # Unity compilation collides in Qt 6.12 QML glue. Retained from the prior
  # baseline pending validation against top-level Nixpkgs 1d060086d60cb76a40cf37109f979d88a5bd6396.
  audacity = prev.audacity.overrideAttrs (old: {
    postPatch = (old.postPatch or "") + ''
      echo 'set_target_properties(muse_extensions_qml PROPERTIES UNITY_BUILD OFF)' \
        >> muse/framework/extensions/qml/Muse/Extensions/CMakeLists.txt
    '';
  });
}
