// Run beside Firefox's PiP actor, which holds the originating video reference.
export class PipVolumeBridgeChild extends JSWindowActorChild {
  receiveMessage({ data }) {
    const video = this.manager.getActor("PictureInPicture").getWeakVideo();
    if (!video || !video.hasAttribute("data-vs-locked-volume")) {
      return false;
    }

    const win = video.ownerDocument.defaultView;
    if (!win) {
      return null;
    }
    const rect = video.getBoundingClientRect();
    const x = Math.max(0, Math.min(win.innerWidth - 1, rect.left + rect.width / 2));
    const y = Math.max(0, Math.min(win.innerHeight - 1, rect.top + rect.height / 2));
    if (!video.ownerDocument.elementsFromPoint(x, y).some(el =>
      el === video || (el !== video.ownerDocument.body && el !== video.ownerDocument.documentElement && el.contains(video))
    )) {
      return false;
    }

    // Volume Scroll prevents the event when it handles the step.
    const handled = !video.dispatchEvent(new win.WheelEvent("wheel", {
      bubbles: true,
      cancelable: true,
      clientX: x,
      clientY: y,
      deltaY: data.direction * -100,
    }));
    if (!handled) {
      return null;
    }

    // The extension updates YouTube's volume panel synchronously, including
    // when a gain node owns the audio and the media element stays at 100%.
    const panel = video.closest(".html5-video-player")?.querySelector(".ytp-volume-panel");
    const panelValue = panel?.getAttribute("aria-valuenow");
    const lockedValue = video.getAttribute("data-vs-locked-volume");
    const volume = panelValue === null || panelValue === undefined
      ? Number(lockedValue) * 100
      : Number(panelValue);
    return { volume: Number.isFinite(volume) ? Math.max(0, Math.min(100, volume)) : null };
  }
}
