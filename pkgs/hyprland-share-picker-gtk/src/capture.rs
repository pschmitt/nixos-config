use std::{
    any::Any,
    collections::HashMap,
    os::fd::OwnedFd,
    sync::mpsc::{
        Receiver, RecvTimeoutError, Sender, SyncSender, TryRecvError, TrySendError, channel,
    },
    thread,
    time::{Duration, Instant},
};

use anyhow::{Context, Result, anyhow};
use libwayshot::{WayshotConnection, WayshotTarget};
use wayland_client::Connection;

/// dmabuf frames per card that may be in flight (owned by GDK) before the
/// worker stops capturing that card. Without this a stalled UI thread would
/// let the worker allocate GPU buffers without bound.
const MAX_INFLIGHT_PER_CARD: usize = 2;

/// Consecutive dmabuf failures tolerated before falling back to the shm path
/// for the rest of the session.
const DMABUF_FAILURE_LIMIT: usize = 3;

/// Paint the pointer into previews so they match what the stream will show.
const CURSOR_OVERLAY: bool = true;

/// Render nodes tried when opening a GBM device for zero-copy capture.
const DRM_DEVICE_CANDIDATES: [&str; 3] = [
    "/dev/dri/renderD128",
    "/dev/dri/renderD129",
    "/dev/dri/renderD130",
];

#[derive(Debug, Clone, PartialEq, Eq, Hash)]
pub enum CaptureTarget {
    Window(String), // stable ID
    Output(String), // monitor name
    Region {
        output: String,
        x: i32,
        y: i32,
        width: u32,
        height: u32,
    },
}

impl CaptureTarget {
    /// The region card is registered before the user has drawn anything, with
    /// a placeholder target that cannot be captured. Capturing it would fail
    /// at the configured refresh rate and log once per attempt.
    fn is_capturable(&self) -> bool {
        match self {
            CaptureTarget::Region {
                output,
                width,
                height,
                ..
            } => !output.is_empty() && *width > 0 && *height > 0,
            _ => true,
        }
    }
}

/// A CPU-side frame: pixels already copied into `bytes`.
#[derive(Clone)]
pub struct FrameData {
    pub width: i32,
    pub height: i32,
    pub stride: usize,
    pub bytes: glib::Bytes,
}

/// A GPU-side frame: the compositor rendered straight into a dmabuf and we
/// only carry its description across. `fd` must stay open until the texture
/// built from it is dropped; the worker keeps the backing buffer object alive
/// until it receives `ReleaseBuffer` for `buffer_id`.
pub struct DmabufFrame {
    pub width: i32,
    pub height: i32,
    pub fourcc: u32,
    pub modifier: u64,
    pub stride: u32,
    pub offset: u32,
    pub fd: OwnedFd,
    pub buffer_id: u64,
}

pub enum FramePayload {
    Shm(FrameData),
    Dmabuf(DmabufFrame),
}

pub struct FrameMessage {
    pub card_id: usize,
    pub frame: FramePayload,
}

#[derive(Debug)]
pub enum CaptureCommand {
    RegisterCard {
        id: usize,
        target: CaptureTarget,
        fps: f32,
        scale: f32,
        tab: String,
    },
    #[allow(dead_code)]
    UnregisterCard {
        id: usize,
    },
    /// An fps of `0.0` or less parks the card without unregistering it.
    SetCardFps {
        id: usize,
        fps: f32,
    },
    SetActiveTab {
        tab: String,
    },
    UpdateRegion {
        id: usize,
        target: CaptureTarget,
    },
    /// Suspends every card, e.g. while the picker hides itself for slurp.
    SetPaused {
        paused: bool,
    },
    /// Re-enumerates toplevels after Hyprland reported window changes.
    RefreshTargets,
    /// The UI is done with a dmabuf frame and its buffer can be freed.
    ReleaseBuffer {
        buffer_id: u64,
    },
    /// GDK refused to import a dmabuf; stop producing them.
    DisableDmabuf,
    Stop,
}

struct CardEntry {
    target: CaptureTarget,
    fps: f32,
    scale: f32,
    tab: String,
    next_capture: Instant,
    last_error_count: usize,
}

pub struct CaptureManager {
    cmd_sender: Sender<CaptureCommand>,
}

impl CaptureManager {
    pub fn new(frame_sender: SyncSender<FrameMessage>) -> Self {
        let (cmd_sender, cmd_receiver) = channel::<CaptureCommand>();
        thread::Builder::new()
            .name("hyprland-capture-worker".into())
            .spawn(move || run_worker(cmd_receiver, frame_sender))
            .expect("spawn capture worker thread");

        Self { cmd_sender }
    }

    /// A clonable handle for callbacks that run outside the UI state, such as
    /// the dmabuf texture release closures (which must be `Send`).
    pub fn command_sender(&self) -> Sender<CaptureCommand> {
        self.cmd_sender.clone()
    }

    pub fn register_card(&self, id: usize, target: CaptureTarget, fps: f32, scale: f32, tab: &str) {
        let _ = self.cmd_sender.send(CaptureCommand::RegisterCard {
            id,
            target,
            fps,
            scale,
            tab: tab.to_string(),
        });
    }

    #[allow(dead_code)]
    pub fn unregister_card(&self, id: usize) {
        let _ = self.cmd_sender.send(CaptureCommand::UnregisterCard { id });
    }

    pub fn set_card_fps(&self, id: usize, fps: f32) {
        let _ = self.cmd_sender.send(CaptureCommand::SetCardFps { id, fps });
    }

    pub fn set_active_tab(&self, tab: &str) {
        let _ = self.cmd_sender.send(CaptureCommand::SetActiveTab {
            tab: tab.to_string(),
        });
    }

    pub fn update_region(&self, id: usize, target: CaptureTarget) {
        let _ = self
            .cmd_sender
            .send(CaptureCommand::UpdateRegion { id, target });
    }

    pub fn set_paused(&self, paused: bool) {
        let _ = self.cmd_sender.send(CaptureCommand::SetPaused { paused });
    }

    pub fn refresh_targets(&self) {
        let _ = self.cmd_sender.send(CaptureCommand::RefreshTargets);
    }
}

impl Drop for CaptureManager {
    fn drop(&mut self) {
        let _ = self.cmd_sender.send(CaptureCommand::Stop);
    }
}

/// Opens a wayshot connection with dmabuf support if any render node works,
/// falling back to a plain shm connection.
fn connect() -> Option<(WayshotConnection, bool)> {
    let mut candidates: Vec<String> = Vec::new();
    if let Some(dev) = std::env::var_os("HYPRLAND_SHARE_PICKER_DRM_DEVICE") {
        candidates.push(dev.to_string_lossy().into_owned());
    }
    candidates.extend(DRM_DEVICE_CANDIDATES.iter().map(|s| s.to_string()));

    for device in &candidates {
        if !std::path::Path::new(device).exists() {
            continue;
        }
        let conn = match Connection::connect_to_env() {
            Ok(c) => c,
            Err(err) => {
                eprintln!("hyprland-share-picker: failed to connect to Wayland: {err:#}");
                return None;
            }
        };
        match WayshotConnection::from_connection_with_dmabuf(conn, device) {
            Ok(c) => return Some((c, true)),
            Err(err) => {
                eprintln!(
                    "hyprland-share-picker: no zero-copy capture via {device}: {err:#} \
                     (falling back to the next device)"
                );
            }
        }
    }

    match WayshotConnection::new() {
        Ok(c) => {
            eprintln!("hyprland-share-picker: using shm capture (no dmabuf device available)");
            Some((c, false))
        }
        Err(err) => {
            eprintln!("hyprland-share-picker: failed to connect to Wayland: {err:#}");
            None
        }
    }
}

struct Worker {
    /// Backing buffers for frames GDK still references, keyed by buffer id.
    /// Declared before the connections so they are dropped before the GBM
    /// device they were allocated from.
    held: HashMap<u64, Box<dyn Any>>,
    /// Connections replaced while their buffers were still in flight. Kept
    /// until nothing references them any more.
    retired: Vec<WayshotConnection>,
    conn: WayshotConnection,
    frame_sender: SyncSender<FrameMessage>,
    cards: HashMap<usize, CardEntry>,
    active_tab: String,
    paused: bool,
    dmabuf: bool,
    dmabuf_failures: usize,
    /// Set when Hyprland reported window changes, so the next window capture
    /// rebuilds the toplevel list first.
    targets_stale: bool,
    inflight: HashMap<usize, Vec<u64>>,
    next_buffer_id: u64,
}

fn run_worker(receiver: Receiver<CaptureCommand>, frame_sender: SyncSender<FrameMessage>) {
    let Some((conn, dmabuf)) = connect() else {
        return;
    };
    debug_dump_toplevels(&conn);

    let mut worker = Worker {
        held: HashMap::new(),
        retired: Vec::new(),
        conn,
        frame_sender,
        cards: HashMap::new(),
        active_tab: "windows".to_string(),
        paused: false,
        dmabuf,
        dmabuf_failures: 0,
        targets_stale: false,
        inflight: HashMap::new(),
        next_buffer_id: 1,
    };

    loop {
        // Drain everything that is already queued before doing any work.
        loop {
            match receiver.try_recv() {
                Ok(cmd) => {
                    if !worker.apply(cmd) {
                        return;
                    }
                }
                Err(TryRecvError::Empty) => break,
                Err(TryRecvError::Disconnected) => return,
            }
        }

        let (due, wait) = worker.due_cards();

        if due.is_empty() {
            match receiver.recv_timeout(wait) {
                Ok(cmd) => {
                    if !worker.apply(cmd) {
                        return;
                    }
                }
                Err(RecvTimeoutError::Timeout) => {}
                Err(RecvTimeoutError::Disconnected) => return,
            }
            continue;
        }

        for id in due {
            worker.capture_card(id);
        }
    }
}

impl Worker {
    /// Returns `false` when the worker should stop.
    fn apply(&mut self, cmd: CaptureCommand) -> bool {
        match cmd {
            CaptureCommand::RegisterCard {
                id,
                target,
                fps,
                scale,
                tab,
            } => {
                self.cards.insert(
                    id,
                    CardEntry {
                        target,
                        fps,
                        scale,
                        tab,
                        next_capture: Instant::now(),
                        last_error_count: 0,
                    },
                );
            }
            CaptureCommand::UnregisterCard { id } => {
                self.cards.remove(&id);
                self.inflight.remove(&id);
            }
            CaptureCommand::SetCardFps { id, fps } => {
                if let Some(card) = self.cards.get_mut(&id) {
                    let was_parked = card.fps <= 0.0;
                    card.fps = fps;
                    if fps > 0.0 && (was_parked || fps >= 10.0) {
                        card.next_capture = Instant::now();
                    }
                }
            }
            CaptureCommand::SetActiveTab { tab } => {
                self.active_tab = tab;
                let now = Instant::now();
                for card in self.cards.values_mut() {
                    if card.tab == self.active_tab {
                        card.next_capture = now;
                    }
                }
            }
            CaptureCommand::UpdateRegion { id, target } => {
                if let Some(card) = self.cards.get_mut(&id) {
                    card.target = target;
                    card.next_capture = Instant::now();
                }
            }
            CaptureCommand::SetPaused { paused } => {
                self.paused = paused;
                if !paused {
                    let now = Instant::now();
                    for card in self.cards.values_mut() {
                        card.next_capture = now;
                    }
                }
            }
            CaptureCommand::RefreshTargets => {
                self.targets_stale = true;
            }
            CaptureCommand::ReleaseBuffer { buffer_id } => {
                self.held.remove(&buffer_id);
                for ids in self.inflight.values_mut() {
                    ids.retain(|id| *id != buffer_id);
                }
                if self.held.is_empty() {
                    self.retired.clear();
                }
            }
            CaptureCommand::DisableDmabuf => {
                if self.dmabuf {
                    eprintln!(
                        "hyprland-share-picker: GDK cannot import our dmabufs, \
                         falling back to shm previews"
                    );
                }
                self.dmabuf = false;
            }
            CaptureCommand::Stop => return false,
        }
        true
    }

    /// Cards that are due for a capture right now, plus how long to sleep when
    /// none are.
    fn due_cards(&self) -> (Vec<usize>, Duration) {
        let mut min_wait = Duration::from_millis(100);
        let mut due: Vec<usize> = Vec::new();

        if self.paused {
            return (due, min_wait);
        }

        let now = Instant::now();
        for (&id, card) in &self.cards {
            if card.tab != self.active_tab || card.fps <= 0.0 {
                continue;
            }
            if self.inflight.get(&id).map(Vec::len).unwrap_or(0) >= MAX_INFLIGHT_PER_CARD {
                continue;
            }
            if now >= card.next_capture {
                due.push(id);
            } else {
                min_wait = min_wait.min(card.next_capture.duration_since(now));
            }
        }

        due.sort_by(|a, b| {
            let fps_a = self.cards.get(a).map(|c| c.fps).unwrap_or(0.0);
            let fps_b = self.cards.get(b).map(|c| c.fps).unwrap_or(0.0);
            fps_b
                .partial_cmp(&fps_a)
                .unwrap_or(std::cmp::Ordering::Equal)
        });

        (due, min_wait.max(Duration::from_millis(1)))
    }

    fn capture_card(&mut self, id: usize) {
        let started = Instant::now();
        let Some((target, scale, fps)) = self
            .cards
            .get(&id)
            .map(|card| (card.target.clone(), card.scale, card.fps))
        else {
            return;
        };

        if !target.is_capturable() {
            if let Some(card) = self.cards.get_mut(&id) {
                card.next_capture = Instant::now() + Duration::from_millis(250);
            }
            return;
        }

        let mut error: Option<anyhow::Error> = None;
        let mut delivered = false;
        let mut used_shm = false;

        // Resolve the source once: both paths need it, and the lookup may
        // rebuild the connection.
        let resolved = match self.resolve_target(&target) {
            Ok(resolved) => resolved,
            Err(err) => {
                error = Some(err);
                None
            }
        };

        if error.is_none() {
            if let (true, Some(source)) = (self.dmabuf, resolved.as_ref()) {
                match self.capture_dmabuf(id, source) {
                    Ok(()) => {
                        self.dmabuf_failures = 0;
                        delivered = true;
                    }
                    Err(err) => {
                        self.dmabuf_failures += 1;
                        if self.dmabuf_failures == 1 {
                            eprintln!(
                                "hyprland-share-picker: zero-copy capture failed for \
                                 {target:?}: {err:#}"
                            );
                        }
                        if self.dmabuf_failures >= DMABUF_FAILURE_LIMIT {
                            eprintln!(
                                "hyprland-share-picker: giving up on zero-copy capture, \
                                 using shm previews"
                            );
                            self.dmabuf = false;
                        }
                    }
                }
            }

            if !delivered {
                used_shm = true;
                let toplevel = match resolved {
                    Some(WayshotTarget::Toplevel(handle)) => Some(handle),
                    _ => None,
                };
                match capture_shm_target(&mut self.conn, &target, scale, toplevel) {
                    Ok(frame) => {
                        let _ = self.frame_sender.try_send(FrameMessage {
                            card_id: id,
                            frame: FramePayload::Shm(frame),
                        });
                        delivered = true;
                    }
                    Err(err) => error = Some(err),
                }
            }
        }

        let Some(card) = self.cards.get_mut(&id) else {
            return;
        };

        if delivered {
            card.last_error_count = 0;
        } else if let Some(err) = error {
            card.last_error_count += 1;
            if card.last_error_count == 1 || card.last_error_count % 10 == 0 {
                eprintln!("hyprland-share-picker: preview capture failed for {target:?}: {err:#}");
            }
        }

        // CPU previews copy and downscale an entire output, including for a
        // region. Keep them below 5 fps and leave at least as much idle time
        // as the capture consumed. The configured high rate is for dmabufs.
        let interval = if used_shm {
            Duration::from_secs_f32(1.0 / fps.clamp(0.2, 5.0)).max(started.elapsed())
        } else {
            Duration::from_secs_f32(1.0 / fps.max(0.2))
        };
        card.next_capture = Instant::now() + interval;
    }

    /// Captures straight into a GPU buffer and hands its dmabuf description to
    /// the UI thread. The buffer object stays alive here until the UI releases
    /// it, so the texture GDK builds keeps pointing at valid memory.
    fn capture_dmabuf(&mut self, id: usize, source: &WayshotTarget) -> Result<()> {
        let (format, guard, bo) = self
            .conn
            .capture_target_frame_dmabuf(source, CURSOR_OVERLAY, None)
            .map_err(|err| anyhow!("{err}"))?;

        let fd = bo
            .fd_for_plane(0)
            .map_err(|err| anyhow!("no dmabuf fd for plane 0: {err}"))?;
        let modifier: u64 = bo.modifier().into();
        let frame = DmabufFrame {
            width: format.size.width as i32,
            height: format.size.height as i32,
            fourcc: format.format,
            modifier,
            stride: bo.stride_for_plane(0),
            offset: bo.offset(0),
            fd,
            buffer_id: self.next_buffer_id,
        };

        self.held
            .insert(self.next_buffer_id, Box::new((guard, bo)) as Box<dyn Any>);
        self.inflight
            .entry(id)
            .or_default()
            .push(self.next_buffer_id);
        self.next_buffer_id += 1;

        let buffer_id = frame.buffer_id;
        if let Err(err) = self.frame_sender.try_send(FrameMessage {
            card_id: id,
            frame: FramePayload::Dmabuf(frame),
        }) {
            // A hidden or stalled UI must not retain frames indefinitely.
            // Release both the queued fd and the worker's backing buffer.
            self.held.remove(&buffer_id);
            if let Some(ids) = self.inflight.get_mut(&id) {
                ids.retain(|held_id| *held_id != buffer_id);
            }
            if matches!(err, TrySendError::Disconnected(_)) {
                return Err(anyhow!("frame channel closed"));
            }
        }

        Ok(())
    }

    /// `Ok(None)` means the target needs the CPU crop path for a region.
    fn resolve_target(&mut self, target: &CaptureTarget) -> Result<Option<WayshotTarget>> {
        match target {
            CaptureTarget::Output(name) => {
                let output = self
                    .conn
                    .get_all_outputs()
                    .iter()
                    .find(|o| o.name == *name)
                    .with_context(|| format!("no Wayland output named {name:?}"))?;
                Ok(Some(WayshotTarget::Screen(output.wl_output.clone())))
            }
            CaptureTarget::Window(stable_id) => Ok(Some(WayshotTarget::Toplevel(
                self.toplevel_handle(stable_id)?,
            ))),
            CaptureTarget::Region { .. } => Ok(None),
        }
    }

    /// Resolves a Hyprland stable ID to a toplevel handle, rebuilding the
    /// connection if the cached list does not have it.
    ///
    /// `WayshotConnection::refresh_toplevels` is deliberately not used: the
    /// compositor announces toplevels once per binding, so its fresh roundtrip
    /// comes back empty and wipes the cached list instead of updating it. A new
    /// connection is the only way to re-enumerate.
    fn toplevel_handle(
        &mut self,
        stable_id: &str,
    ) -> Result<libwayshot::reexport::ExtForeignToplevelHandleV1> {
        if self.targets_stale {
            self.reconnect();
        }

        if let Some(handle) = self.find_toplevel(stable_id) {
            return Ok(handle);
        }

        self.reconnect();
        self.find_toplevel(stable_id)
            .with_context(|| format!("no toplevel matched stable ID {stable_id:?}"))
    }

    fn reconnect(&mut self) {
        self.targets_stale = false;

        let Some((conn, dmabuf)) = connect() else {
            return;
        };

        let previous = std::mem::replace(&mut self.conn, conn);
        if self.held.is_empty() {
            drop(previous);
        } else {
            // Buffers allocated from this connection's GBM device are still
            // on screen; keep it until they come back.
            self.retired.push(previous);
        }

        self.dmabuf = self.dmabuf && dmabuf;
        debug_dump_toplevels(&self.conn);
    }

    fn find_toplevel(
        &self,
        stable_id: &str,
    ) -> Option<libwayshot::reexport::ExtForeignToplevelHandleV1> {
        self.conn
            .get_all_toplevels()
            .iter()
            .find(|toplevel| toplevel.identifier == stable_id)
            .map(|toplevel| toplevel.handle.clone())
    }
}

/// Dumps the toplevel list when HYPRLAND_SHARE_PICKER_DEBUG is set, to debug
/// preview targets that will not bind.
fn debug_dump_toplevels(conn: &WayshotConnection) {
    if std::env::var_os("HYPRLAND_SHARE_PICKER_DEBUG").is_none() {
        return;
    }
    let toplevels: Vec<String> = conn
        .get_all_toplevels()
        .iter()
        .map(|t| format!("{}={}", t.identifier, t.app_id))
        .collect();
    eprintln!(
        "hyprland-share-picker: {} toplevel(s): {}",
        toplevels.len(),
        toplevels.join(" ")
    );
}

/// Turns a single-output screenshot the way the output shows it. For a
/// rotated output libwayshot hands back the panel's native orientation:
/// on a 270° panel (gk4) a portrait frame that needs a quarter turn
/// clockwise, as `--probe-capture` showed. A frame whose orientation
/// disagrees with the output's logical size gets that turn.
fn upright(
    image: image::DynamicImage,
    output: &libwayshot::output::OutputInfo,
) -> image::DynamicImage {
    use libwayshot::reexport::Transform;
    let logical = output.logical_region.inner.size;
    if (image.width() >= image.height()) == (logical.width >= logical.height) {
        return image;
    }
    match output.transform {
        Transform::_90 | Transform::Flipped90 => image.rotate270(),
        Transform::_270 | Transform::Flipped270 => image.rotate90(),
        _ => image,
    }
}

/// Debug aid (`--probe-capture OUTPUT PREFIX`): captures `name` the way
/// shm previews do and writes `PREFIX-raw.jpg` (libwayshot's frame) and
/// `PREFIX-upright.jpg` (after `upright`), printing sizes and timings.
pub fn probe_output(name: &str, prefix: &str) -> Result<()> {
    let (connection, _) = connect().context("no Wayland connection")?;
    let output = connection
        .get_all_outputs()
        .iter()
        .find(|o| o.name == name)
        .cloned()
        .with_context(|| format!("no Wayland output named {name:?}"))?;
    let logical = output.logical_region.inner.size;
    eprintln!(
        "output {name}: transform {:?}, logical {}x{}",
        output.transform, logical.width, logical.height
    );
    for _ in 0..3 {
        let started = Instant::now();
        let raw = connection.screenshot_single_output(&output, CURSOR_OVERLAY)?;
        let captured = started.elapsed();
        let fixed = upright(raw.clone(), &output);
        let preview_started = Instant::now();
        let preview = upright(downscale(raw.clone(), 0.35), &output);
        eprintln!(
            "preview path {}x{} in {:?}",
            preview.width(),
            preview.height(),
            preview_started.elapsed()
        );
        eprintln!(
            "raw {}x{} in {captured:?}, upright {}x{} after {:?}",
            raw.width(),
            raw.height(),
            fixed.width(),
            fixed.height(),
            started.elapsed()
        );
        raw.to_rgb8().save(format!("{prefix}-raw.jpg"))?;
        fixed.to_rgb8().save(format!("{prefix}-upright.jpg"))?;
    }
    Ok(())
}

/// Scales a captured frame down to preview size. `thumbnail_exact` is a box
/// filter: for the large downscales previews ask for it is dramatically
/// cheaper than a triangle-filtered resize, whose kernel support grows with
/// the scale factor.
fn downscale(image: image::DynamicImage, scale: f32) -> image::DynamicImage {
    let target_w = ((image.width() as f32 * scale).round() as u32).max(1);
    let target_h = ((image.height() as f32 * scale).round() as u32).max(1);
    image.thumbnail_exact(target_w, target_h)
}

fn capture_shm_target(
    connection: &mut WayshotConnection,
    target: &CaptureTarget,
    scale: f32,
    toplevel: Option<libwayshot::reexport::ExtForeignToplevelHandleV1>,
) -> Result<FrameData> {
    let image = match target {
        CaptureTarget::Output(name) => {
            let output = connection
                .get_all_outputs()
                .iter()
                .find(|o| o.name == *name)
                .with_context(|| format!("no Wayland output named {name:?}"))?;
            let image = connection.screenshot_single_output(output, CURSOR_OVERLAY)?;
            upright(downscale(image, scale), output)
        }
        CaptureTarget::Region {
            output,
            x,
            y,
            width,
            height,
        } => {
            let out = connection
                .get_all_outputs()
                .iter()
                .find(|candidate| candidate.name == *output)
                .with_context(|| format!("no Wayland output named {output:?}"))?;
            // libwayshot's ext-image-copy backend ignores capture_region but
            // labels the full frame as that region. Capture the output first
            // and crop its transformed pixels ourselves on either backend.
            let logical = out.logical_region.inner.size;
            if *x < 0 || *y < 0 || logical.width == 0 || logical.height == 0 {
                return Err(anyhow!("region is outside the output"));
            }
            // Shrink before turning and cropping: both are cheap on the
            // preview-sized frame and costly on the full output.
            let image = connection.screenshot_single_output(out, CURSOR_OVERLAY)?;
            let image = upright(downscale(image, scale), out);
            let pixel_x = |value: u32| {
                ((u64::from(value) * u64::from(image.width())) / u64::from(logical.width))
                    .min(u64::from(image.width())) as u32
            };
            let pixel_y = |value: u32| {
                ((u64::from(value) * u64::from(image.height())) / u64::from(logical.height))
                    .min(u64::from(image.height())) as u32
            };
            let left = pixel_x(*x as u32);
            let top = pixel_y(*y as u32);
            let right = pixel_x((*x as u32).saturating_add(*width));
            let bottom = pixel_y((*y as u32).saturating_add(*height));
            if right <= left || bottom <= top {
                return Err(anyhow!("region does not intersect the output"));
            }
            image.crop_imm(left, top, right - left, bottom - top)
        }
        CaptureTarget::Window(_) => {
            let handle =
                toplevel.context("the shm window path needs a resolved toplevel handle")?;
            downscale(
                connection.screenshot_toplevel(&handle, CURSOR_OVERLAY)?,
                scale,
            )
        }
    };

    let rgba = image.into_rgba8();

    let width = rgba.width() as i32;
    let height = rgba.height() as i32;
    let stride = (width * 4) as usize;
    let bytes = glib::Bytes::from_owned(rgba.into_raw());

    Ok(FrameData {
        width,
        height,
        stride,
        bytes,
    })
}
