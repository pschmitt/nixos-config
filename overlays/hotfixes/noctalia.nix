# Patch bundle consumed by ../noctalia.nix at explicit positions so the
# original interleaving with feature patches is preserved.
# Reviewed 2026-11-12 against Noctalia c2573248a89470383e41b8e1ac432424691cbc1f
# and Nixpkgs f4a03c008967841f2a0b3cb7c436fc6fc31671f6. The patched package builds.
# These are local fixes with no upstream issue recorded yet. Remove each when
# the pinned source implements the corresponding correction.
{
  # Render plugin images at their device-pixel size without unwanted blur.
  sharpImages = ../patches/noctalia/0002-sharp-ui-image.patch;

  keyboardAndCapture = [
    # Select the physical main keyboard and recover its layout after IPC startup.
    ../patches/noctalia/0005-hyprland-main-keyboard-layout.patch

    # Do not show a layout-change OSD before the initial layout is known.
    ../patches/noctalia/0006-keyboard-layout-osd-prime.patch

    # Avoid transforming an already output-transformed screencopy frame twice.
    ../patches/noctalia/0007-screencopy-transformed-dimensions.patch
  ];
}
