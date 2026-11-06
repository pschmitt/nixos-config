{ inputs, final }:
{
  # Deliberate input customization: allow a service-specific keymap for remote
  # input without changing the local compositor's physical keyboard layout.
  lan-mouse =
    inputs.lan-mouse.packages.${final.stdenv.hostPlatform.system}.default.overrideAttrs
      (_old: {
        src = final.applyPatches {
          name = "lan-mouse-patched";
          src = inputs.lan-mouse;
          patches = [
            ../pkgs/local/lan-mouse/0001-env-keymap.patch
            ../pkgs/local/lan-mouse/0002-input-state.patch
          ];
        };
      });
}
