{
  inputs,
  final,
  prev,
}:
let
  inherit (final.stdenv.hostPlatform) system;
  base = inputs.hyprgrass.packages.${system}.default;
in
{
  hyprgrass = base.overrideAttrs (old: {
    # Hyprland 0.56 moved fullscreen state off CWindow (isFullscreen() is gone,
    # query via Fullscreen::controller() instead) and made
    # CGeometricMovableAnimated::m_real{Position,Size} protected (use the
    # public positionAnimation()/sizeAnimation() accessors). Upstream hasn't
    # released a compatible commit yet.
    patches = (old.patches or [ ]) ++ [
      ./patches/hyprgrass/0001-hyprland-0.56-api-compat.patch
    ];
  });
}

# vim: set ft=nix et ts=2 sw=2 :
