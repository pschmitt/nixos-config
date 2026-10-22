// Mouse controls for the Picture-in-Picture window, like the YouTube player:
// - scroll over the video to change the volume, with the same volume bar
//   overlay and scroll behavior as the Volume Scroll extension
// - click the video to play/pause
// - a play/pause icon flashes in the middle whenever playback starts or stops,
//   whatever caused it (click, the play/pause button, space, media keys)
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
// Click to play/pause: Firefox's PiP window does nothing on a single click on
// the video (the click lands on the #controls overlay; only a double click is
// handled, for fullscreen). Clicks on #controls therefore press PiP's own
// #playpause button, so its state and controls handling stay intact. A double
// click toggles twice (net no change) before going fullscreen, as in YouTube.
//
// The icon is driven by PiP's own play state: PiP toggles the "playing" class on
// #controls whenever the originating video starts or stops, so a MutationObserver
// on it covers every way of toggling. Changes during the first moments after
// the window opens are the initial state, not a toggle, and are ignored.
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

  const SVG_NS = "http://www.w3.org/2000/svg";
  const STATE_ICON_MS = 600;
  // Play state changes this soon after opening are the initial state
  const STATE_SETTLE_MS = 1000;
  // A press that moved further than this is a window drag, not a click
  const CLICK_SLOP_PX = 5;

  // The originating player echoes every change back and the PiP window then
  // resets its slider to the echoed value. Step from our own target (in whole
  // percent) instead of the slider, or a stale echo between two wheel ticks
  // swallows the scroll.
  let target = null;
  let idleTimer = null;
  let scrollAccumulator = 0;
  let lastScrollTime = 0;
  let overlay = null;
  let stateIcon = null;
  let pressX = 0;
  let pressY = 0;

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

  // YouTube style play/pause flash: a white glyph on a translucent disc in the
  // middle of the video that fades out while growing.
  const createStateIcon = doc => {
    const root = doc.createElement("div");
    Object.assign(root.style, {
      position: "fixed",
      top: "50%",
      left: "50%",
      width: "104px",
      height: "104px",
      marginTop: "-52px",
      marginLeft: "-52px",
      borderRadius: "50%",
      backgroundColor: "rgba(0, 0, 0, 0.6)",
      display: "none",
      alignItems: "center",
      justifyContent: "center",
      pointerEvents: "none",
      zIndex: "9999999",
    });
    const svg = doc.createElementNS(SVG_NS, "svg");
    svg.setAttribute("viewBox", "0 0 24 24");
    svg.setAttribute("width", "60");
    svg.setAttribute("height", "60");
    svg.setAttribute("fill", "#ffffff");
    root.appendChild(svg);
    doc.body.appendChild(root);

    const shape = (tag, attrs) => {
      const el = doc.createElementNS(SVG_NS, tag);
      for (const [name, value] of Object.entries(attrs)) {
        el.setAttribute(name, value);
      }
      svg.appendChild(el);
    };

    let animation = null;
    return {
      // started: playback was just started (play icon), else paused (pause icon)
      show(started) {
        svg.replaceChildren();
        if (started) {
          shape("path", {
            d: "M8 5.5v13c0 .8.9 1.3 1.6.8l10-6.5c.6-.4.6-1.2 0-1.6l-10-6.5C8.9 4.2 8 4.7 8 5.5z",
          });
        } else {
          shape("rect", { x: "6", y: "5", width: "4", height: "14", rx: "1.5" });
          shape("rect", { x: "14", y: "5", width: "4", height: "14", rx: "1.5" });
        }
        root.style.display = "flex";

        animation?.cancel();
        animation = root.animate(
          [
            { opacity: 1, transform: "scale(1)" },
            { opacity: 0, transform: "scale(1.4)" },
          ],
          { duration: STATE_ICON_MS, easing: "ease-out", fill: "forwards" }
        );
      },
    };
  };

  const onClick = (win, event) => {
    // Only the bare video surface; buttons, the scrubber and panels have their
    // own ids. Presses that moved were a window drag.
    if (
      event.button !== 0 ||
      event.target.id !== "controls" ||
      Math.abs(event.screenX - pressX) > CLICK_SLOP_PX ||
      Math.abs(event.screenY - pressY) > CLICK_SLOP_PX
    ) {
      return;
    }
    win.document.getElementById("playpause").click();
  };

  // Flash the icon whenever the play state flips, see the header comment
  const watchPlayState = win => {
    const doc = win.document;
    const controls = doc.getElementById("controls");
    const openedAt = Date.now();
    let playing = controls.classList.contains("playing");
    new win.MutationObserver(() => {
      const now = controls.classList.contains("playing");
      if (now === playing) {
        return;
      }
      playing = now;
      if (Date.now() - openedAt < STATE_SETTLE_MS) {
        return;
      }
      stateIcon ??= createStateIcon(doc);
      // Started playing: play icon. Paused: pause icon.
      stateIcon.show(now);
    }).observe(controls, { attributes: true, attributeFilter: ["class"] });
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
          stateIcon = null;
          target = null;
          win.document.addEventListener("wheel", e => onWheel(win, e), {
            passive: false,
          });
          win.document.addEventListener("mousedown", e => {
            pressX = e.screenX;
            pressY = e.screenY;
          });
          win.document.addEventListener("click", e => onClick(win, e));
          watchPlayState(win);
        },
        { once: true }
      );
    },
  });
})();
