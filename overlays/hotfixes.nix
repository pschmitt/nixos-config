{
  # final,
  # inputs,
  prev,
  ...
}:

{
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
