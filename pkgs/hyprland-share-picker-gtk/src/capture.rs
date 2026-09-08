use std::{
    collections::HashMap,
    sync::mpsc::{Receiver, Sender, channel},
    thread,
    time::{Duration, Instant},
};

use anyhow::{Context, Result};
use image::imageops::FilterType;
use libwayshot::{
    WayshotConnection,
    region::{LogicalRegion, Position, Region, Size},
};

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

#[derive(Clone)]
pub struct FrameData {
    pub width: i32,
    pub height: i32,
    pub stride: usize,
    pub bytes: glib::Bytes,
}

pub struct FrameMessage {
    pub card_id: usize,
    pub frame: FrameData,
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
}

impl Drop for CaptureManager {
    fn drop(&mut self) {
        let _ = self.cmd_sender.send(CaptureCommand::Stop);
    }
}

fn run_worker(receiver: Receiver<CaptureCommand>, frame_sender: Sender<FrameMessage>) {
    let mut connection = match WayshotConnection::new() {
        Ok(c) => c,
        Err(err) => {
            eprintln!("hyprland-share-picker: failed to connect to Wayland: {err:#}");
            return;
        }
    };

    let mut cards: HashMap<usize, CardEntry> = HashMap::new();
    let mut active_tab = "windows".to_string();

    loop {
        // Drain pending commands
        while let Ok(cmd) = receiver.try_recv() {
            match cmd {
                CaptureCommand::RegisterCard {
                    id,
                    target,
                    fps,
                    scale,
                    tab,
                } => {
                    cards.insert(
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
                    cards.remove(&id);
                }
                CaptureCommand::SetCardFps { id, fps } => {
                    if let Some(card) = cards.get_mut(&id) {
                        card.fps = fps;
                        if fps >= 10.0 {
                            card.next_capture = Instant::now();
                        }
                    }
                }
                CaptureCommand::SetActiveTab { tab } => {
                    active_tab = tab;
                    for card in cards.values_mut() {
                        if card.tab == active_tab {
                            card.next_capture = Instant::now();
                        }
                    }
                }
                CaptureCommand::UpdateRegion { id, target } => {
                    if let Some(card) = cards.get_mut(&id) {
                        card.target = target;
                        card.next_capture = Instant::now();
                    }
                }
                CaptureCommand::Stop => return,
            }
        }

        let now = Instant::now();
        let mut min_wait = Duration::from_millis(50);
        let mut capture_candidates: Vec<usize> = Vec::new();

        for (&id, card) in &cards {
            if card.tab != active_tab {
                continue;
            }
            if now >= card.next_capture {
                capture_candidates.push(id);
            } else {
                let wait = card.next_capture.duration_since(now);
                if wait < min_wait {
                    min_wait = wait;
                }
            }
        }

        capture_candidates.sort_by(|&a, &b| {
            let fps_a = cards.get(&a).map(|c| c.fps).unwrap_or(0.0);
            let fps_b = cards.get(&b).map(|c| c.fps).unwrap_or(0.0);
            fps_b
                .partial_cmp(&fps_a)
                .unwrap_or(std::cmp::Ordering::Equal)
        });

        for id in capture_candidates {
            let (target, scale, fps) = match cards.get(&id) {
                Some(card) => (card.target.clone(), card.scale, card.fps),
                None => continue,
            };

            let frame_res = capture_single_target(&mut connection, &target, scale);
            let card = match cards.get_mut(&id) {
                Some(c) => c,
                None => continue,
            };

            match frame_res {
                Ok(frame) => {
                    card.last_error_count = 0;
                    let _ = frame_sender.send(FrameMessage { card_id: id, frame });
                }
                Err(err) => {
                    card.last_error_count += 1;
                    if card.last_error_count == 1 || card.last_error_count % 10 == 0 {
                        eprintln!(
                            "hyprland-share-picker: preview capture failed for {target:?}: {err:#}"
                        );
                    }
                }
            }

            let interval = Duration::from_secs_f32(1.0 / fps.max(0.2));
            card.next_capture = Instant::now() + interval;
        }

        if let Ok(cmd) = receiver
            .recv_timeout(min_wait.clamp(Duration::from_millis(1), Duration::from_millis(100)))
        {
            match cmd {
                CaptureCommand::RegisterCard {
                    id,
                    target,
                    fps,
                    scale,
                    tab,
                } => {
                    cards.insert(
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
                    cards.remove(&id);
                }
                CaptureCommand::SetCardFps { id, fps } => {
                    if let Some(card) = cards.get_mut(&id) {
                        card.fps = fps;
                        if fps >= 10.0 {
                            card.next_capture = Instant::now();
                        }
                    }
                }
                CaptureCommand::SetActiveTab { tab } => {
                    active_tab = tab;
                    for card in cards.values_mut() {
                        if card.tab == active_tab {
                            card.next_capture = Instant::now();
                        }
                    }
                }
                CaptureCommand::UpdateRegion { id, target } => {
                    if let Some(card) = cards.get_mut(&id) {
                        card.target = target;
                        card.next_capture = Instant::now();
                    }
                }
                CaptureCommand::Stop => return,
            }
        }
    }
}

fn capture_single_target(
    connection: &mut WayshotConnection,
    target: &CaptureTarget,
    scale: f32,
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
        CaptureTarget::Window(stable_id) => {
            let toplevel_opt = connection
                .get_all_toplevels()
                .iter()
                .find(|toplevel| toplevel.identifier == *stable_id)
                .cloned();

            let toplevel = match toplevel_opt {
                Some(t) => t,
                None => {
                    if let Ok(new_conn) = WayshotConnection::new() {
                        *connection = new_conn;
                    }
                    connection
                        .get_all_toplevels()
                        .iter()
                        .find(|toplevel| toplevel.identifier == *stable_id)
                        .cloned()
                        .with_context(|| format!("no toplevel matched stable ID {stable_id:?}"))?
                }
            };
            connection.screenshot_toplevel(&toplevel, false)?
        }
    };

    let target_w = ((image.width() as f32 * scale).round() as u32).max(1);
    let target_h = ((image.height() as f32 * scale).round() as u32).max(1);
    let scaled = image.resize_exact(target_w, target_h, FilterType::Triangle);
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
