use std::{
    any::Any,
    collections::HashMap,
    os::fd::OwnedFd,
    sync::mpsc::{Receiver, RecvTimeoutError, Sender, TryRecvError, channel},
    thread,
    time::{Duration, Instant},
};

use anyhow::{Context, Result, anyhow};
use libwayshot::{
    WayshotConnection, WayshotTarget,
    region::{LogicalRegion, Position, Region, Size},
};
use wayland_client::Connection;

/// dmabuf frames per card that may be in flight (owned by GDK) before the
/// worker stops capturing that card. Without this a stalled UI thread would
/// let the worker allocate GPU buffers without bound.
const MAX_INFLIGHT_PER_CARD: usize = 2;

/// Consecutive dmabuf failures tolerated before falling back to the shm path
/// for the rest of the session.
const DMABUF_FAILURE_LIMIT: usize = 3;

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
    pub fn new(frame_sender: Sender<FrameMessage>) -> Self {
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
    frame_sender: Sender<FrameMessage>,
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

fn run_worker(receiver: Receiver<CaptureCommand>, frame_sender: Sender<FrameMessage>) {
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
                let toplevel = match resolved {
                    Some(WayshotTarget::Toplevel(handle)) => Some(handle),
                    _ => None,
                };
                match capture_shm_target(&mut self.conn, &target, scale, toplevel) {
                    Ok(frame) => {
                        let _ = self.frame_sender.send(FrameMessage {
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

        let interval = Duration::from_secs_f32(1.0 / fps.max(0.2));
        card.next_capture = Instant::now() + interval;
    }

    /// Captures straight into a GPU buffer and hands its dmabuf description to
    /// the UI thread. The buffer object stays alive here until the UI releases
    /// it, so the texture GDK builds keeps pointing at valid memory.
    fn capture_dmabuf(&mut self, id: usize, source: &WayshotTarget) -> Result<()> {
        let (format, guard, bo) = self
            .conn
            .capture_target_frame_dmabuf(source, false, None)
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

        self.frame_sender
            .send(FrameMessage {
                card_id: id,
                frame: FramePayload::Dmabuf(frame),
            })
            .map_err(|_| anyhow!("frame channel closed"))?;

        Ok(())
    }

    /// `Ok(None)` means the target has no ext-image-copy source: regions are
    /// captured through wlr-screencopy's region path instead.
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
            connection.screenshot_single_output(output, false)?
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
            let output_region = out.logical_region;
            let region = LogicalRegion {
                inner: Region {
                    position: Position {
                        x: output_region.inner.position.x + x,
                        y: output_region.inner.position.y + y,
                    },
                    size: Size {
                        width: *width,
                        height: *height,
                    },
                },
            };
            connection.screenshot(region, false)?
        }
        CaptureTarget::Window(_) => {
            let handle = toplevel
                .context("the shm window path needs a resolved toplevel handle")?;
            connection.screenshot_toplevel(&handle, false)?
        }
    };

    let target_w = ((image.width() as f32 * scale).round() as u32).max(1);
    let target_h = ((image.height() as f32 * scale).round() as u32).max(1);
    // `thumbnail_exact` is a box filter: for the large downscales previews ask
    // for it is dramatically cheaper than a triangle-filtered resize, whose
    // kernel support grows with the scale factor.
    let scaled = image.thumbnail_exact(target_w, target_h);
    let rgba = scaled.into_rgba8();

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
