// Scroll over the Picture-in-Picture window to change the volume, with the
// same volume bar overlay and scroll behavior as the Volume Scroll extension.
//
// Why this is an autoconfig script and not an extension: the PiP window is a
// privileged chrome document (chrome://global/content/pictureinpicture/
// player.xhtml), so WebExtensions such as Volume Scroll cannot inject content
// scripts into it and never see wheel events over it.
//
// How it works: watch for new windows, and when the PiP player opens, listen
// for "wheel" on it. Each step moves the player's own audio slider and fires
// the slider's "input" event, exactly like dragging it by hand. PiP then sends
// PictureInPicture:SetVolume to the originating video; on sites with a PiP
// video wrapper (YouTube, ...) that goes through the site's own player API, so
// the page's volume control stays in sync as well. Driving the slider (instead
// of messaging the actor directly) also keeps the PiP widget itself in sync and
// reuses PiP's mute/unmute handling when reaching 0.
//
// Volume Scroll settings: SETTINGS below is a snapshot of the extension's
// settings (pip-volume-scroll.settings.json, injected at build time by
// pip-volume-scroll.nix). The step logic and the bar overlay are ported from
// https://github.com/FredrikWilhelmsen/Volume-Scroll (handlers/Default.tsx and
// components/overlays/BarOverlay.tsx). Only the "bar" overlay style is
// implemented, and volume boost is not (PiP's slider tops out at 100%).
//
// The PiP document has a "default-src chrome:" CSP, which blocks inline <style>
// elements and style attributes, so the overlay is styled through CSSOM
// (element.style) and faded with the Web Animations API.
//
// Do not use backticks, dollar signs or backslashes in this file: the nixpkgs
// Firefox wrapper writes it into mozilla.cfg through an unquoted shell heredoc,
// which expands them and breaks the script (so no template literals).
//
// Fragile by nature: relies on the #audio-scrubber id and the slider's event
// handling in player.xhtml/player.js (checked against Firefox 158).
(() => {
  const PIP_URL = "chrome://global/content/pictureinpicture/player.xhtml";
  const SETTINGS = @VOLUME_SCROLL_SETTINGS@;

  // Volume Scroll accumulates wheel deltas until a full "notch" (50) is reached
  const SCROLL_THRESHOLD = 50;
  const SCROLL_RESET_MS = 500;
  const IDLE_MS = 400;
  const FADE_MS = 250;

  // The originating player echoes every change back and the PiP window then
  // resets its slider to the echoed value. Step from our own target (in whole
  // percent) instead of the slider, or a stale echo between two wheel ticks
  // swallows the scroll.
  let target = null;
  let idleTimer = null;
  let scrollAccumulator = 0;
  let lastScrollTime = 0;
  let overlay = null;

  // Port of Volume Scroll's updateVolume(): returns the new volume in percent.
  const nextVolume = (previous, direction) => {
    if (SETTINGS.invertScrollDirection) {
      direction *= -1;
    }
    let increment = SETTINGS.volumeIncrement;
    let threshold = increment;

    // Finer steps (1%) at the quiet end of the range
    if (SETTINGS.usePreciseScroll) {
      if (SETTINGS.useCustomPreciseScrollThreshold) {
        threshold = SETTINGS.customPreciseScrollThreshold;
      }
      if (
        (direction === -1 && previous <= threshold) ||
        (direction === 1 && previous < threshold)
      ) {
        increment = 1;
      }
    }

    let volume = previous + increment * direction;
    // Snap back onto the increment grid if we started off it
    if (SETTINGS.useRoundToNearestIncrement && volume > threshold) {
      volume = Math.round(volume / increment) * increment;
    }
    return Math.min(100, Math.max(0, volume));
  };

  // Port of BarOverlay.tsx, reduced to what the PiP window needs.
  const createOverlay = doc => {
    const make = (parent, styles) => {
      const el = doc.createElement("div");
      Object.assign(el.style, styles);
      parent.appendChild(el);
      return el;
    };

    const side = SETTINGS.overlayBarSide;
    const isRight = side === "right";
    const isBottom = side === "bottom";
    const isHorizontal = side === "top" || side === "bottom";
    const angle = SETTINGS.dutchAngleValue;
    const background = SETTINGS.useOverlayBackground
      ? "rgba(30, 30, 30, " + SETTINGS.overlayBackgroundOpacity / 100 + ")"
      : "transparent";

    let rotation = "";
    if (SETTINGS.useDutchAngle) {
      const sign = isHorizontal ? (isBottom ? -1 : 1) : isRight ? 1 : -1;
      rotation = "rotate(" + sign * angle + "deg)";
    }
    const vertical = isHorizontal ? (isBottom ? "bottom" : "top") : null;
    const horizontal = isRight ? "right" : "left";
    const origin = isHorizontal
      ? (angle < 0 ? "right" : "left") + " " + vertical
      : horizontal + " " + (angle < 0 ? "bottom" : "top");

    const root = make(doc.body, {
      position: "fixed",
      zIndex: "9999999",
      pointerEvents: "none",
      display: "none",
      alignItems: "flex-start",
      flexDirection: isHorizontal
        ? isBottom
          ? "column-reverse"
          : "column"
        : isRight
          ? "row-reverse"
          : "row",
      transform: [isBottom ? "translateY(-100%)" : "", rotation]
        .filter(Boolean)
        .join(" "),
      transformOrigin: origin,
      ...(isHorizontal
        ? {
            left: "10%",
            width: "80%",
            [isBottom ? "bottom" : "top"]: "20px",
          }
        : { top: "10%", height: "80%", [horizontal]: "20px" }),
    });

    const showNumber = SETTINGS.showNumericValue;
    const radius = "12px";
    const barRadius = isHorizontal
      ? showNumber
        ? isBottom
          ? "0 0 " + radius + " " + radius
          : radius + " " + radius + " 0 0"
        : radius
      : isRight
        ? showNumber
          ? "0 " + radius + " " + radius + " " + radius
          : radius
        : showNumber
          ? radius + " 0 " + radius + " " + radius
          : radius;

    const wrapper = make(root, {
      backgroundColor: background,
      width: isHorizontal ? "100%" : "auto",
      height: isHorizontal ? "auto" : "100%",
      padding: "16px",
      boxSizing: "border-box",
      borderRadius: barRadius,
    });
    const container = make(wrapper, {
      position: "relative",
      width: isHorizontal ? "100%" : "40px",
      height: isHorizontal ? "40px" : "100%",
      border: "4px solid " + SETTINGS.overlayColor,
      padding: "8px",
      boxSizing: "border-box",
    });
    const fillContainer = make(container, {
      position: "relative",
      width: "100%",
      height: "100%",
      overflow: "hidden",
    });
    const fill = make(fillContainer, {
      position: "absolute",
      bottom: "0",
      left: "0",
      width: "100%",
      height: "100%",
      backgroundColor: SETTINGS.overlayColor,
      transition: (isHorizontal ? "width" : "height") + " 0.1s ease-out",
    });

    let number = null;
    if (showNumber) {
      const numberWrapper = make(root, {
        backgroundColor: background,
        padding: "16px",
        boxSizing: "border-box",
        borderRadius: isHorizontal
          ? isBottom
            ? radius + " " + radius + " 0 0"
            : "0 0 " + radius + " " + radius
          : isRight
            ? radius + " 0 0 " + radius
            : "0 " + radius + " " + radius + " 0",
      });
      number = make(numberWrapper, {
        fontWeight: "bold",
        fontFamily: "Roboto, Arial, sans-serif",
        textShadow:
          "-1px -1px 0 #000, 1px -1px 0 #000, -1px 1px 0 #000, 1px 1px 0 #000",
        color: SETTINGS.overlayColor,
        fontSize: SETTINGS.fontSize * 0.85 + "px",
        lineHeight: "1",
      });
    }

    let animation = null;
    return {
      show(volume) {
        fill.style[isHorizontal ? "width" : "height"] = volume + "%";
        if (number) {
          number.textContent = Math.round(volume);
        }
        root.style.display = "flex";

        // Restart the fade on every step. Duration 0 means "stay visible".
        animation?.cancel();
        const duration = SETTINGS.overlayDuration;
        if (duration === 0) {
          return;
        }
        const fadeStart = duration > FADE_MS ? (duration - FADE_MS) / duration : 0;
        animation = root.animate(
          [
            { opacity: 1, offset: 0 },
            { opacity: 1, offset: fadeStart },
            { opacity: 0, offset: 1 },
          ],
          { duration, fill: "forwards" }
        );
      },
    };
  };

  const onWheel = (win, event) => {
    const slider = win.document.getElementById("audio-scrubber");
    const delta = event.deltaY || event.deltaX;
    if (!slider || !delta) {
      return;
    }
    event.preventDefault();

    // Accumulate until a full notch, like Volume Scroll does, so that touchpads
    // don't fire a step per pixel
    const now = Date.now();
    if (now - lastScrollTime > SCROLL_RESET_MS) {
      scrollAccumulator = 0;
    }
    lastScrollTime = now;
    scrollAccumulator +=
      event.deltaMode === 1 ? delta * 33.3 : event.deltaMode === 2 ? delta * 333 : delta;
    if (Math.abs(scrollAccumulator) < SCROLL_THRESHOLD) {
      return;
    }
    const direction = scrollAccumulator > 0 ? -1 : 1;
    scrollAccumulator = 0;

    // A muted video keeps the slider's max at 0
    slider.max = 1;
    if (target === null) {
      target = Math.round(Number(slider.value) * 100);
    }
    target = nextVolume(target, direction);
    slider.value = target / 100;
    slider.dispatchEvent(new win.Event("input", { bubbles: true }));
    slider.dispatchEvent(new win.Event("change", { bubbles: true }));

    if (SETTINGS.useOverlay) {
      overlay ??= createOverlay(win.document);
      overlay.show(target);
    }

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
          // Per-window state: a new PiP window starts without an overlay
          overlay = null;
          target = null;
          win.document.addEventListener("wheel", e => onWheel(win, e), {
            passive: false,
          });
        },
        { once: true }
      );
    },
  });
})();
