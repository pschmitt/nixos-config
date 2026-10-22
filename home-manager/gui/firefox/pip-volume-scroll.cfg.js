// Scroll over the Picture-in-Picture window to change the volume.
//
// Why this is an autoconfig script and not an extension: the PiP window is a
// privileged chrome document (chrome://global/content/pictureinpicture/
// player.xhtml), so WebExtensions such as Volume Scroll cannot inject content
// scripts into it and never see wheel events over it.
//
// How it works: watch for new windows, and when the PiP player opens, listen
// for `wheel` on it. Each tick moves the player's own audio slider and fires
// the slider's `input` event, exactly like dragging it by hand. PiP then sends
// PictureInPicture:SetVolume to the originating video; on sites with a PiP
// video wrapper (YouTube, ...) that goes through the site's own player API, so
// the page's volume control stays in sync as well. Driving the slider (instead
// of messaging the actor directly) also keeps the PiP widget itself in sync and
// reuses PiP's mute/unmute handling when reaching 0.
//
// Fragile by nature: relies on the #audio-scrubber id and the slider's event
// handling in player.xhtml/player.js (checked against Firefox 158).
(() => {
  const PIP_URL = "chrome://global/content/pictureinpicture/player.xhtml";
  const STEP = 0.05;
  const IDLE_MS = 400;

  // The originating player echoes every change back and the PiP window then
  // resets its slider to the echoed value. Step from our own target instead of
  // the slider, or a stale echo between two wheel ticks swallows the scroll.
  let target = null;
  let idleTimer = null;

  const onWheel = (win, event) => {
    const slider = win.document.getElementById("audio-scrubber");
    if (!slider || !event.deltaY) {
      return;
    }
    event.preventDefault();
    // A muted video keeps the slider's max at 0
    slider.max = 1;
    if (target === null) {
      target = Number(slider.value);
    }
    const direction = event.deltaY < 0 ? 1 : -1;
    // Whole percent: YouTube's setVolume floors fractional values
    target = Math.round(Math.min(1, Math.max(0, target + direction * STEP)) * 100) / 100;
    slider.value = target;
    slider.dispatchEvent(new win.Event("input", { bubbles: true }));
    slider.dispatchEvent(new win.Event("change", { bubbles: true }));

    win.clearTimeout(idleTimer);
    idleTimer = win.setTimeout(() => {
      target = null;
    }, IDLE_MS);
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
