{ inputs, final }:
{
  # Deliberate input customization: allow a service-specific keymap for remote
  # input without changing the local compositor's physical keyboard layout.
  lan-mouse =
    inputs.lan-mouse.packages.${final.stdenv.hostPlatform.system}.default.overrideAttrs
      (old: {
        src = final.applyPatches {
          name = "lan-mouse-patched";
          src = inputs.lan-mouse;
          patches = [
            ../pkgs/local/lan-mouse/0001-env-keymap.patch
            ../pkgs/local/lan-mouse/0002-input-state.patch
          ];
        };
        # lan-mouse 0.11.0 uses libgit2-sys, and Nixpkgs disables vendoring.
        # Reviewed 2026-11-10 at Nixpkgs
        # f4a03c008967841f2a0b3cb7c436fc6fc31671f6; without these inputs,
        # the build cannot find a compatible system libgit2. Remove when the
        # lan-mouse flake package supplies these dependencies itself.
        nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ final.pkg-config ];
        buildInputs = (old.buildInputs or [ ]) ++ [ final.libgit2 ];
      });
}
