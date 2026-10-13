{ pkgs, ... }:
{
  services.browser-daemon = {
    # An X display per session, so each session's screen can be captured on its own
    displayMode = "per-session";
    # and streamed to the handoff view as H.264, encoded on the Intel GPU: an
    # animated page cost ~13% of a core this way vs ~147% as a JPEG screencast.
    video = {
      enable = true;
      encoder = "vaapi";
    };
  };

  # VAAPI driver for the Comet Lake iGPU (Mesa ships none for Intel).
  hardware.graphics.extraPackages = [ pkgs.intel-media-driver ];
}
