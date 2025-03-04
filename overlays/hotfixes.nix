{
  inputs,
  final,
  prev,
}:
{
  droidcam-obs-patched =
    inputs.droidcam-obs.legacyPackages.${final.system}.obs-studio-plugins.droidcam-obs;

  aerc = inputs.aerc.legacyPackages.${final.system}.aerc;
  notmuch = inputs.notmuch.legacyPackages.${final.system}.notmuch;
}
