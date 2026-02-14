{
  # final,
  # inputs,
  prev,
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

  # FIX For google-chrome crashing on Hyprland when moving the window from
  # one monitor to another.
  # https://github.com/hyprwm/Hyprland/discussions/11843
  google-chrome = prev.google-chrome.overrideAttrs (old: {
    nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ prev.makeWrapper ];
    postFixup = (old.postFixup or "") + ''
      wrapProgram $out/bin/google-chrome-stable \
        --add-flags "--disable-features=WaylandWpColorManagerV1"
    '';
  });

  # TODO Remove once https://github.com/NixOS/nixpkgs/pull/xxx reaches
  # nixos-unstable
  # inherit (inputs.nixpkgs-xxx.legacyPackages.${final.stdenv.hostPlatform.system}) PKGNAME;

  # Ensure python313Packages uses the modified interpreter
  # python313Packages = final.python313.pkgs;
}
