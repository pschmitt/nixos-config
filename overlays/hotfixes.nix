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

  # TODO Remove once https://github.com/NixOS/nixpkgs/pull/467572 lands
  v4l2loopback =
    let
      base =
        prev.v4l2loopback or (prev.callPackage "${prev.path}/pkgs/os-specific/linux/v4l2loopback" {
          kernel = null;
          kernelModuleMakeFlags = [ ];
        });
    in
    base.overrideAttrs (old: rec {
      version = "0.15.3";

      src = prev.fetchFromGitHub {
        owner = "umlaeute";
        repo = "v4l2loopback";
        tag = "v${version}";
        hash = "sha256-KXJgsEJJTr4TG4Ww5HlF42v2F1J+AsHwrllUP1n/7g8=";
      };

      passthru = (old.passthru or { }) // {
        updateScript = prev."nix-update-script" { };
      };
    });

  # Ensure python313Packages uses the modified interpreter
  # python313Packages = final.python313.pkgs;

  # Make sure kernel-specific package sets also use the patched v4l2loopback
  linuxPackages = prev.linuxPackages.extend (
    self: _super: {
      v4l2loopback = final.v4l2loopback.override { kernel = self.kernel; };
    }
  );

  linuxPackages_latest = prev.linuxPackages_latest.extend (
    self: _super: {
      v4l2loopback = final.v4l2loopback.override { kernel = self.kernel; };
    }
  );

  linuxPackages_6_18 = prev.linuxPackages_6_18.extend (
    self: _super: {
      v4l2loopback = final.v4l2loopback.override { kernel = self.kernel; };
    }
  );

  # https://github.com/NixOS/nixpkgs/pull/465400
  termbench-pro = prev.termbench-pro.overrideAttrs (old: {
    buildInputs = [
      prev.fmt
      (prev.glaze.override { enableSSL = false; })
    ];
  });
}
