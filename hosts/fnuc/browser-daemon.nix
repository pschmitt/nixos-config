{ pkgs, ... }:
{
  services.browser-daemon = {
    # The live view's H.264 encoded on the Intel GPU: an animated page cost ~13%
    # of a core this way vs ~67% with x264 and ~147% as a JPEG screencast.
    video.encoder = "vaapi";
    # Render Chromium on the iGPU too: WebGL then reports the Intel GPU instead
    # of a software renderer, a bot tell.
    gpu.enable = true;
  };

  # VAAPI driver for the Comet Lake iGPU (Mesa ships none for Intel).
  hardware.graphics.extraPackages = [ pkgs.intel-media-driver ];
}
