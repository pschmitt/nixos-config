{
  final,
  prev,
  # inputs,
  ...
}:

{
  # droidcam-obs-patched =
  #   inputs.droidcam-obs.legacyPackages.${final.system}.obs-studio-plugins.droidcam-obs;

  # TODO Remove once https://github.com/NixOS/nixpkgs/pull/419713 reaches
  # nixos-unstable
  # -> https://nixpk.gs/pr-tracker.html?pr=419713
  # python313 = prev.python313.override {
  #   packageOverrides = python-final: python-prev: {
  #     # FIX FAIL: test_host_whitelist_invalid (tests.test_clean.CleanerTest.test_host_whitelist_invalid)
  #     # See: https://github.com/NixOS/nixpkgs/issues/418689
  #     # Related PR: https://github.com/NixOS/nixpkgs/pull/419520
  #     lxml-html-clean = python-prev.lxml-html-clean.overridePythonAttrs (oldAttrs: {
  #       # disable running tests entirely (simplest fix)
  #       doCheck = false;
  #     });
  #   };
  # };

  # Ensure python313Packages uses the modified interpreter
  python313Packages = final.python313.pkgs;
}
