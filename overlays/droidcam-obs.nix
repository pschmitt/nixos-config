{ final, prev }:
let
  pr =
    import
      (builtins.fetchGit {
        url = "https://github.com/NixOS/nixpkgs.git";
        ref = "refs/pull/382559/head";
      })
      {
        system = builtins.currentSystem;
        overlays = [ ];
      };
in
{
  droidcam-obs-patched = pr.obs-studio-plugins.droidcam-obs;
}
