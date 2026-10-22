// Scroll over the Picture-in-Picture window to change the volume.
//
// The PiP window is a chrome document, so WebExtensions (volume-scroll)
// cannot reach it. Instead drive its own audio slider: that sends the same
// PictureInPicture:SetVolume message as dragging the slider by hand and keeps
// the widget in sync.
(() => {
  const PIP_URL = "chrome://global/content/pictureinpicture/player.xhtml";
  const STEP = 0.05;

  const onWheel = (win, event) => {
    const slider = win.document.getElementById("audio-scrubber");
    if (!slider || !event.deltaY) {
      return;
    }
    event.preventDefault();
    // A muted video keeps the slider's max at 0
    slider.max = 1;
    const direction = event.deltaY < 0 ? 1 : -1;
    const volume = Math.min(1, Math.max(0, Number(slider.value) + direction * STEP));
    slider.value = volume;
    slider.dispatchEvent(new win.Event("input", { bubbles: true }));
    slider.dispatchEvent(new win.Event("change", { bubbles: true }));
  };

  Services.ww.registerNotification({
    observe(subject, topic) {
      if (topic !== "domwindowopened") {
        return;
      }
      const win = subject;
      win.addEventListener(
        "load",
        () => {
          if (win.document.documentURI !== PIP_URL) {
            return;
          }
          win.document.addEventListener("wheel", e => onWheel(win, e), {
            passive: false,
          });
        },
        { once: true }
      );
    },
  });
})();
