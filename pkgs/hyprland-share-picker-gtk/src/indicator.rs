//! Border drawn around a shared region or window while its screencast runs.
//!
//! The picker exits as soon as it reports a selection, so the indicator runs
//! as a detached copy of this binary (`--indicator <target>`). It watches
//! PipeWire for the stream XDPH creates for that share and exits when the
//! stream node disappears, whatever ended it.

use std::{
    collections::{HashMap, HashSet},
    io::{BufRead, BufReader, Write},
    os::{fd::AsRawFd, unix::process::CommandExt},
    process::{self, Command, Stdio},
    rc::Rc,
    sync::mpsc::{Receiver, Sender, TryRecvError, channel},
    thread,
    time::{Duration, Instant},
};

use gtk4::{Application, DrawingArea, Window, cairo, gdk, gio, glib, prelude::*};
use gtk4_layer_shell::{Edge, KeyboardMode, Layer, LayerShell};

use crate::{
    config::{DEFAULT_HIGHLIGHT_RGBA, load_config, parse_rgba_color},
    css::install_css,
    hyprland::{
        Client, Monitor, PortalWindowEntry, Rect, client_for_entry, parse_region_details,
        query_clients, query_monitors,
    },
};

const INDICATOR_APP_ID: &str = "lol.brkn.HyprlandShareIndicator";
/// How long the share may take to show up as a PipeWire node.
const STREAM_START_TIMEOUT: Duration = Duration::from_secs(20);
/// How long the picker waits for the indicator to snapshot existing streams.
const READY_TIMEOUT: Duration = Duration::from_secs(2);
const WINDOW_POLL: Duration = Duration::from_millis(200);
const REGION_POLL: Duration = Duration::from_secs(2);
const PORTAL_BINARY: &str = "xdg-desktop-portal-hyprland";

/// Maps a picker selection to an indicator target. Screens get none: a
/// border on a shared output would end up in the stream.
pub fn target_for_selection(selection: &str, entries: &[PortalWindowEntry]) -> Option<String> {
    if selection.starts_with("region:") {
        return Some(selection.to_string());
    }
    let id = selection.strip_prefix("window:")?;
    let clients = query_clients();
    let client = match entries.iter().find(|entry| entry.id == id) {
        Some(entry) => client_for_entry(entry, &clients),
        None => clients
            .iter()
            .find(|c| c.stable_id_string().as_deref() == Some(id)),
    }?;
    Some(format!("client:{}", client.address))
}

/// Starts the detached indicator and waits until it has recorded the streams
/// that already exist, so the share's own node cannot slip into that set.
pub fn spawn(target: &str) {
    let Ok(exe) = std::env::current_exe() else {
        return;
    };
    let mut cmd = Command::new(exe);
    cmd.args(["--indicator", target])
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        // XDPH reads the picker's stdout and stderr; the indicator must not
        // keep either open.
        .stderr(Stdio::null());
    // SAFETY: setsid and close_range are async-signal-safe and touch no
    // Rust state.
    unsafe {
        cmd.pre_exec(|| {
            libc::setsid();
            // XDPH reads the picker's output until every copy of its pipe is
            // closed, and the picker inherits a stray copy above stderr.
            // Without this the indicator keeps it open and the stream only
            // starts once the indicator exits.
            libc::syscall(
                libc::SYS_close_range,
                3u32,
                u32::MAX,
                libc::CLOSE_RANGE_CLOEXEC,
            );
            Ok(())
        });
    }
    let Ok(mut child) = cmd.spawn() else {
        return;
    };
    let Some(stdout) = child.stdout.take() else {
        return;
    };
    let (tx, rx) = channel();
    thread::spawn(move || {
        let mut line = String::new();
        let _ = BufReader::new(stdout).read_line(&mut line);
        let _ = tx.send(());
    });
    let _ = rx.recv_timeout(READY_TIMEOUT);
}

enum Target {
    Region(String),
    Client(String),
}

enum StreamEvent {
    Ready,
    Started,
    Ended,
}

/// Global rectangle to outline plus the outputs it may be drawn on.
#[derive(Clone, PartialEq)]
struct Outline {
    rect: Rect,
    outputs: Vec<String>,
}

pub fn run(raw_target: &str) -> ! {
    let target = if raw_target.starts_with("region:") {
        Target::Region(raw_target.to_string())
    } else if let Some(address) = raw_target.strip_prefix("client:") {
        Target::Client(address.to_string())
    } else {
        process::exit(2);
    };

    let stream_rx = spawn_stream_watcher();
    let ready = matches!(
        stream_rx.recv_timeout(READY_TIMEOUT),
        Ok(StreamEvent::Ready)
    );
    // Release the picker either way, then drop the pipe for good.
    let _ = std::io::stdout().write_all(b"ready\n");
    let _ = std::io::stdout().flush();
    if let Ok(null) = std::fs::OpenOptions::new().write(true).open("/dev/null") {
        // SAFETY: replaces fd 1 with /dev/null; nothing else holds it.
        unsafe {
            libc::dup2(null.as_raw_fd(), 1);
        }
    }
    if !ready {
        eprintln!("hyprland-share-indicator: PipeWire snapshot unavailable");
        process::exit(1);
    }

    let outline_rx = spawn_outline_watcher(target);

    let app = Application::builder()
        .application_id(INDICATOR_APP_ID)
        .flags(gio::ApplicationFlags::NON_UNIQUE)
        .build();
    let stream_rx = Rc::new(stream_rx);
    let outline_rx = Rc::new(outline_rx);
    app.connect_activate(move |app| {
        build(app, stream_rx.clone(), outline_rx.clone());
    });
    let status = app.run_with_args::<&str>(&[]);
    eprintln!("hyprland-share-indicator: exiting ({status:?})");
    process::exit(0);
}

struct MonitorBorder {
    window: Window,
    area: DrawingArea,
    geom: gdk::Rectangle,
    rect: Rc<std::cell::Cell<Option<Rect>>>,
}

fn build(
    app: &Application,
    stream_rx: Rc<Receiver<StreamEvent>>,
    outline_rx: Rc<Receiver<Outline>>,
) {
    let Some(display) = gdk::Display::default() else {
        process::exit(1);
    };
    if !gtk4_layer_shell::is_supported() {
        process::exit(1);
    }
    install_css();
    let config = load_config();
    let (r, g, b, _) = parse_rgba_color(&config.highlight_color, DEFAULT_HIGHLIGHT_RGBA);
    let width = config.highlight_border_size.max(3.0);

    let mut borders: HashMap<String, MonitorBorder> = HashMap::new();
    let monitors = display.monitors();
    for i in 0..monitors.n_items() {
        let Some(mon) = monitors.item(i).and_downcast::<gdk::Monitor>() else {
            continue;
        };
        let Some(connector) = mon.connector() else {
            continue;
        };
        borders.insert(
            connector.to_string(),
            create_border(app, &mon, (r, g, b), width),
        );
    }

    // Holds the app alive while no window is visible.
    let hold = app.hold();
    let app = app.clone();
    let started_at = Instant::now();
    let mut streaming = false;
    glib::timeout_add_local(Duration::from_millis(100), move || {
        let _ = &hold;
        loop {
            match stream_rx.try_recv() {
                Ok(StreamEvent::Started) => {
                    eprintln!("hyprland-share-indicator: stream started");
                    streaming = true;
                }
                Ok(StreamEvent::Ready) => {}
                Ok(StreamEvent::Ended) | Err(TryRecvError::Disconnected) => {
                    eprintln!("hyprland-share-indicator: stream ended");
                    app.quit();
                    return glib::ControlFlow::Break;
                }
                Err(TryRecvError::Empty) => break,
            }
        }
        if !streaming && started_at.elapsed() > STREAM_START_TIMEOUT {
            eprintln!("hyprland-share-indicator: no stream appeared");
            app.quit();
            return glib::ControlFlow::Break;
        }
        if let Some(outline) = outline_rx.try_iter().last() {
            for (connector, border) in &borders {
                let rect = outline
                    .outputs
                    .contains(connector)
                    .then(|| relative_rect(outline.rect, border.geom, width))
                    .flatten();
                border.rect.set(rect);
                border.window.set_visible(rect.is_some());
                border.area.queue_draw();
            }
        }
        glib::ControlFlow::Continue
    });
}

fn create_border(
    app: &Application,
    mon: &gdk::Monitor,
    (r, g, b): (f64, f64, f64),
    width: f64,
) -> MonitorBorder {
    let window = Window::new();
    window.set_application(Some(app));
    window.init_layer_shell();
    window.set_layer(Layer::Overlay);
    window.set_keyboard_mode(KeyboardMode::None);
    window.set_exclusive_zone(-1);
    window.set_namespace("hyprland-share-indicator");
    for edge in [Edge::Top, Edge::Bottom, Edge::Left, Edge::Right] {
        window.set_anchor(edge, true);
    }
    window.set_monitor(mon);
    window.add_css_class("overlay-highlighter");

    let rect = Rc::new(std::cell::Cell::new(None::<Rect>));
    let area = DrawingArea::new();
    let rect_draw = rect.clone();
    area.set_draw_func(move |_area, cr, _w, _h| {
        let _ = cr.save();
        cr.set_operator(cairo::Operator::Clear);
        let _ = cr.paint();
        let _ = cr.restore();
        let Some(rect) = rect_draw.get() else {
            return;
        };
        // Stroke just outside the target so region streams never see it.
        let half = width / 2.0;
        cr.rectangle(
            rect.x as f64 - half,
            rect.y as f64 - half,
            rect.width as f64 + width,
            rect.height as f64 + width,
        );
        cr.set_source_rgba(r, g, b, 0.95);
        cr.set_line_width(width);
        let _ = cr.stroke();
    });
    window.set_child(Some(&area));
    window.connect_map(|w| {
        if let Some(surface) = w.surface() {
            surface.set_input_region(&cairo::Region::create());
        }
    });

    MonitorBorder {
        window,
        area,
        geom: mon.geometry(),
        rect,
    }
}

/// Converts a global rectangle to monitor-local coordinates when its border
/// touches the monitor at all. The rectangle itself is not clipped, so a
/// border spanning two outputs lines up on both.
fn relative_rect(global: Rect, geom: gdk::Rectangle, width: f64) -> Option<Rect> {
    let pad = width.ceil() as i32;
    let touches = global.x - pad < geom.x() + geom.width()
        && global.x + global.width + pad > geom.x()
        && global.y - pad < geom.y() + geom.height()
        && global.y + global.height + pad > geom.y();
    touches.then(|| Rect {
        x: global.x - geom.x(),
        y: global.y - geom.y(),
        width: global.width,
        height: global.height,
    })
}

/// Polls Hyprland on a worker thread (IPC blocks on a socket) and reports
/// the outline whenever it changes.
fn spawn_outline_watcher(target: Target) -> Receiver<Outline> {
    let (tx, rx) = channel();
    thread::spawn(move || {
        let mut last: Option<Outline> = None;
        loop {
            let monitors = query_monitors();
            if !monitors.is_empty() {
                let outline = match &target {
                    Target::Region(sel) => region_outline(sel, &monitors),
                    Target::Client(address) => {
                        let clients = query_clients();
                        if clients.is_empty() {
                            last.clone()
                        } else {
                            Some(client_outline(address, &clients, &monitors))
                        }
                    }
                };
                if let Some(outline) = outline {
                    if last.as_ref() != Some(&outline) {
                        if tx.send(outline.clone()).is_err() {
                            return;
                        }
                        last = Some(outline);
                    }
                }
            }
            thread::sleep(match target {
                Target::Region(_) => REGION_POLL,
                Target::Client(_) => WINDOW_POLL,
            });
        }
    });
    rx
}

fn region_outline(selection: &str, monitors: &[Monitor]) -> Option<Outline> {
    let details = parse_region_details(selection, monitors)?;
    Some(Outline {
        rect: Rect {
            x: details.global_x,
            y: details.global_y,
            width: details.width as i32,
            height: details.height as i32,
        },
        outputs: monitors.iter().map(|m| m.name.clone()).collect(),
    })
}

/// A closed or hidden window yields an outline with no outputs.
fn client_outline(address: &str, clients: &[Client], monitors: &[Monitor]) -> Outline {
    let client = clients
        .iter()
        .find(|c| c.address == address)
        .filter(|c| c.at.len() == 2 && c.size.len() == 2);
    match client {
        Some(c) => Outline {
            rect: Rect {
                x: c.at[0],
                y: c.at[1],
                width: c.size[0],
                height: c.size[1],
            },
            outputs: monitors
                .iter()
                .filter(|m| c.is_visible_on_monitor(m))
                .map(|m| m.name.clone())
                .collect(),
        },
        None => Outline {
            rect: Rect {
                x: 0,
                y: 0,
                width: 0,
                height: 0,
            },
            outputs: Vec::new(),
        },
    }
}

/// Follows `pw-dump --monitor`: the first batch is the full graph, later
/// batches carry changed objects, and `{"id": N, "info": null}` marks a
/// removal. Event driven, so it costs nothing while the graph is idle.
fn spawn_stream_watcher() -> Receiver<StreamEvent> {
    let (tx, rx) = channel();
    thread::spawn(move || {
        watch_streams(&tx);
        let _ = tx.send(StreamEvent::Ended);
    });
    rx
}

fn watch_streams(tx: &Sender<StreamEvent>) {
    let mut cmd = Command::new("pw-dump");
    cmd.args(["--monitor", "--no-colors"])
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::null());
    // SAFETY: prctl is async-signal-safe; pw-dump must not outlive us.
    unsafe {
        cmd.pre_exec(|| {
            libc::prctl(libc::PR_SET_PDEATHSIG, libc::SIGTERM);
            Ok(())
        });
    }
    let Ok(mut child) = cmd.spawn() else {
        return;
    };
    let Some(stdout) = child.stdout.take() else {
        return;
    };

    let mut portal_clients: HashSet<u64> = HashSet::new();
    // Node ID -> owning client ID.
    let mut nodes: HashMap<u64, u64> = HashMap::new();
    let mut baseline: Option<HashSet<u64>> = None;
    let mut claimed: Option<u64> = None;

    let batches = serde_json::Deserializer::from_reader(BufReader::new(stdout))
        .into_iter::<Vec<serde_json::Value>>();
    for batch in batches {
        let Ok(batch) = batch else {
            break;
        };
        for object in &batch {
            let Some(id) = object.get("id").and_then(|v| v.as_u64()) else {
                continue;
            };
            let info = object.get("info").filter(|v| !v.is_null());
            let Some(info) = info else {
                if claimed == Some(id) {
                    let _ = child.kill();
                    return;
                }
                portal_clients.remove(&id);
                nodes.remove(&id);
                continue;
            };
            let props = info.get("props");
            match object.get("type").and_then(|v| v.as_str()) {
                Some("PipeWire:Interface:Client") => {
                    if let Some(binary) = props
                        .and_then(|p| p.get("application.process.binary"))
                        .and_then(|v| v.as_str())
                    {
                        if binary.contains(PORTAL_BINARY) {
                            portal_clients.insert(id);
                        } else {
                            portal_clients.remove(&id);
                        }
                    }
                }
                Some("PipeWire:Interface:Node") => {
                    if let Some(client) = props
                        .and_then(|p| p.get("client.id"))
                        .and_then(|v| v.as_u64())
                    {
                        nodes.insert(id, client);
                    }
                }
                _ => {}
            }
        }

        let portal_nodes = nodes
            .iter()
            .filter(|(_, client)| portal_clients.contains(client))
            .map(|(node, _)| *node);
        match &baseline {
            None => {
                baseline = Some(portal_nodes.collect());
                if tx.send(StreamEvent::Ready).is_err() {
                    break;
                }
            }
            Some(existing) if claimed.is_none() => {
                let mut fresh: Vec<u64> = portal_nodes.filter(|n| !existing.contains(n)).collect();
                fresh.sort_unstable();
                if let Some(node) = fresh.first() {
                    claimed = Some(*node);
                    if tx.send(StreamEvent::Started).is_err() {
                        break;
                    }
                }
            }
            Some(_) => {}
        }
    }
    let _ = child.kill();
}
