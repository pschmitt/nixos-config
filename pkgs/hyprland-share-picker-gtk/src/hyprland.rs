use std::{
    env, fs,
    io::{Read, Write},
    os::unix::net::UnixStream,
    path::PathBuf,
    process::Command,
    sync::mpsc::{Receiver, RecvTimeoutError, Sender, channel},
    thread,
    time::Duration,
};

use regex::Regex;
use serde::{Deserialize, Serialize};

pub const PICKER_APP_ID: &str = "lol.brkn.HyprlandSharePicker";

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Workspace {
    // Hyprland omits the ID when no special workspace is active.
    #[serde(default)]
    pub id: i64,
    pub name: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Client {
    pub address: String,
    #[serde(default, rename = "stableId")]
    pub stable_id: Option<serde_json::Value>,
    #[serde(default)]
    pub at: Vec<i32>,
    #[serde(default)]
    pub size: Vec<i32>,
    pub workspace: Workspace,
    #[serde(default)]
    pub title: String,
    #[serde(default)]
    pub class: String,
    #[serde(default, rename = "initialClass")]
    pub initial_class: String,
    #[serde(default, rename = "initialTitle")]
    pub initial_title: String,
    #[serde(default, rename = "focusHistoryID")]
    pub focus_history_id: Option<i64>,
    #[serde(default)]
    pub pinned: bool,
    #[serde(default)]
    pub floating: bool,
    #[serde(default)]
    pub hidden: bool,
    #[serde(default = "default_mapped")]
    pub mapped: bool,
}

fn default_mapped() -> bool {
    true
}

impl Client {
    pub fn stable_id_string(&self) -> Option<String> {
        self.stable_id.as_ref().map(|v| match v {
            serde_json::Value::String(s) => s.clone(),
            serde_json::Value::Number(n) => n.to_string(),
            _ => v.to_string(),
        })
    }

    pub fn is_visible_on_monitor(&self, monitor: &Monitor) -> bool {
        if !self.mapped || self.hidden {
            return false;
        }
        if self.pinned {
            return true;
        }
        monitor
            .active_workspace
            .as_ref()
            .map_or(false, |w| w.id == self.workspace.id)
            || monitor
                .special_workspace
                .as_ref()
                .map_or(false, |w| w.id != 0 && w.id == self.workspace.id)
    }

    pub fn is_visible_on_any_monitor(&self, monitors: &[Monitor]) -> bool {
        if !self.mapped || self.hidden {
            return false;
        }
        if self.pinned {
            return true;
        }
        monitors.iter().any(|m| self.is_visible_on_monitor(m))
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Monitor {
    pub id: i64,
    pub name: String,
    #[serde(default)]
    pub description: String,
    pub width: i32,
    pub height: i32,
    #[serde(default)]
    pub x: i32,
    #[serde(default)]
    pub y: i32,
    #[serde(default)]
    pub scale: f64,
    #[serde(default)]
    pub focused: bool,
    #[serde(default, rename = "activeWorkspace")]
    pub active_workspace: Option<Workspace>,
    #[serde(default, rename = "specialWorkspace")]
    pub special_workspace: Option<Workspace>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ActiveWorkspace {
    pub id: i64,
    pub name: String,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PortalWindowEntry {
    pub id: String,
    pub class: String,
    pub title: String,
    pub address: Option<String>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Rect {
    pub x: i32,
    pub y: i32,
    pub width: i32,
    pub height: i32,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RegionDetails {
    pub output: String,
    pub x: i32,
    pub y: i32,
    pub width: u32,
    pub height: u32,
    pub global_x: i32,
    pub global_y: i32,
}

pub fn parse_window_list(raw: &str) -> Vec<PortalWindowEntry> {
    let re = Regex::new(
        r"(?P<id>\d+)\[HC>](?P<class>.*?)\[HT>](?P<title>.*?)\[HE>](?:(?P<address>0x[0-9a-fA-F]+|\d+)\[HA>])?"
    ).unwrap();

    re.captures_iter(raw)
        .filter(|cap| &cap["class"] != PICKER_APP_ID)
        .map(|cap| {
            let address = cap.name("address").map(|m| {
                let s = m.as_str();
                if s.starts_with("0x") || s.starts_with("0X") {
                    s.to_lowercase()
                } else if let Ok(num) = s.parse::<u64>() {
                    format!("0x{:x}", num)
                } else {
                    s.to_string()
                }
            });

            PortalWindowEntry {
                id: cap["id"].to_string(),
                class: cap["class"].to_string(),
                title: cap["title"].to_string(),
                address,
            }
        })
        .collect()
}

pub fn client_for_entry<'a>(
    entry: &PortalWindowEntry,
    clients: &'a [Client],
) -> Option<&'a Client> {
    if let Some(ref addr) = entry.address {
        if let Some(c) = clients.iter().find(|c| c.address == *addr) {
            return Some(c);
        }
    }

    if let Some(c) = clients
        .iter()
        .find(|c| c.stable_id_string().as_deref() == Some(&entry.id))
    {
        return Some(c);
    }

    let by_title: Vec<&Client> = clients
        .iter()
        .filter(|c| c.class == entry.class && c.title == entry.title)
        .collect();
    if let Some(first) = by_title.first() {
        return Some(first);
    }

    let by_class: Vec<&Client> = clients.iter().filter(|c| c.class == entry.class).collect();
    if by_class.len() == 1 {
        return Some(by_class[0]);
    }

    None
}

pub fn parse_region(raw: &str, monitors: &[Monitor]) -> Option<String> {
    let fields: Vec<&str> = raw.split_whitespace().collect();
    if fields.len() != 5 {
        return None;
    }

    let output = fields[0];
    let gx: i32 = fields[1].parse().ok()?;
    let gy: i32 = fields[2].parse().ok()?;
    let w: u32 = fields[3].parse().ok()?;
    let h: u32 = fields[4].parse().ok()?;

    if w == 0 || h == 0 {
        return None;
    }

    let mon = monitors.iter().find(|m| m.name == output)?;
    let rel_x = gx - mon.x;
    let rel_y = gy - mon.y;

    Some(format!("region:{output}@{rel_x},{rel_y},{w},{h}"))
}

pub fn parse_region_details(selection: &str, monitors: &[Monitor]) -> Option<RegionDetails> {
    let raw = selection.strip_prefix("region:")?;
    let (output, rest) = raw.split_once('@')?;
    let coords: Vec<&str> = rest.split(',').collect();
    if coords.len() != 4 {
        return None;
    }

    let x: i32 = coords[0].parse().ok()?;
    let y: i32 = coords[1].parse().ok()?;
    let width: u32 = coords[2].parse().ok()?;
    let height: u32 = coords[3].parse().ok()?;

    let mon = monitors.iter().find(|m| m.name == output)?;
    Some(RegionDetails {
        output: output.to_string(),
        x,
        y,
        width,
        height,
        global_x: mon.x + x,
        global_y: mon.y + y,
    })
}

pub fn window_to_region(client: &Client, monitors: &[Monitor]) -> Option<String> {
    if client.at.len() < 2 || client.size.len() < 2 {
        return None;
    }
    let (gx, gy) = (client.at[0], client.at[1]);
    let (w, h) = (client.size[0] as u32, client.size[1] as u32);
    if w == 0 || h == 0 {
        return None;
    }

    let mon = monitors
        .iter()
        .find(|m| gx >= m.x && gx < m.x + m.width && gy >= m.y && gy < m.y + m.height)
        .or_else(|| monitors.first())?;

    let rel_x = gx - mon.x;
    let rel_y = gy - mon.y;
    Some(format!(
        "region:{}@{},{},{},{}",
        mon.name, rel_x, rel_y, w, h
    ))
}

pub fn hyprland_instance_signature() -> Option<String> {
    if let Ok(his) = env::var("HYPRLAND_INSTANCE_SIGNATURE") {
        if !his.is_empty() {
            return Some(his);
        }
    }

    let uid = rustix::process::getuid().as_raw();
    let hypr_dir = PathBuf::from(format!("/run/user/{uid}/hypr"));
    if let Ok(entries) = fs::read_dir(hypr_dir) {
        for entry in entries.flatten() {
            if entry.path().join(".socket.sock").exists() {
                return entry.file_name().into_string().ok();
            }
        }
    }

    None
}

/// A coalesced snapshot of everything the picker reads from Hyprland.
pub struct HyprState {
    pub clients: Vec<Client>,
    pub monitors: Vec<Monitor>,
    pub active_workspace: Option<i64>,
    /// Set when the set of windows differs from the previous snapshot.
    pub windows_changed: bool,
}

/// Longest gap between snapshots when Hyprland reports nothing.
const STATE_IDLE_REFRESH: Duration = Duration::from_millis(2000);
/// Quiet period that ends a burst of window events.
const STATE_EVENT_DEBOUNCE: Duration = Duration::from_millis(120);

/// Watches Hyprland's event socket and turns event bursts into coalesced state
/// snapshots on a worker thread. The IPC queries block on a unix socket, so
/// they must never run on the UI thread.
pub fn spawn_state_watcher() -> Receiver<HyprState> {
    let (state_tx, state_rx) = channel::<HyprState>();
    let (event_tx, event_rx) = channel::<()>();

    let _listener = listen_socket2(move |msg| {
        if msg.starts_with("openwindow>>")
            || msg.starts_with("closewindow>>")
            || msg.starts_with("windowtitle")
            || msg.starts_with("movewindow")
            || msg.starts_with("workspace")
        {
            let _ = event_tx.send(());
        }
    });

    let spawned = thread::Builder::new()
        .name("hypr-state".into())
        .spawn(move || {
            let mut previous: Vec<String> = Vec::new();
            let mut first = true;

            loop {
                match event_rx.recv_timeout(STATE_IDLE_REFRESH) {
                    Ok(()) => {
                        // Hyprland emits these in bursts; wait for quiet.
                        while event_rx.recv_timeout(STATE_EVENT_DEBOUNCE).is_ok() {}
                    }
                    Err(RecvTimeoutError::Timeout) => {}
                    // No event socket: keep the periodic refresh going anyway.
                    Err(RecvTimeoutError::Disconnected) => thread::sleep(STATE_IDLE_REFRESH),
                }

                let clients = query_clients();
                let addresses: Vec<String> = clients.iter().map(|c| c.address.clone()).collect();
                // The first snapshot is not a change: the UI queried the same
                // state when it started, and reporting one would make the
                // capture worker rebuild its connection for nothing.
                let windows_changed = !first && addresses != previous;
                previous = addresses;
                first = false;

                let snapshot = HyprState {
                    clients,
                    monitors: query_monitors(),
                    active_workspace: query_active_workspace().map(|workspace| workspace.id),
                    windows_changed,
                };

                if state_tx.send(snapshot).is_err() {
                    return;
                }
            }
        });

    if spawned.is_err() {
        eprintln!("hyprland-share-picker: could not spawn the Hyprland state watcher");
    }

    state_rx
}

/// Track only the picker's bounds while highlight overlays are visible. The
/// compositor owns toplevel positioning; Wayland clients cannot read it from
/// GDK. Keep this polling off the UI thread and stop it when overlays are hidden.
pub fn spawn_picker_bounds_watcher() -> (Sender<bool>, Receiver<Rect>) {
    let (control_tx, control_rx) = channel::<bool>();
    let (bounds_tx, bounds_rx) = channel();
    thread::Builder::new()
        .name("picker-bounds".into())
        .spawn(move || {
            while let Ok(enabled) = control_rx.recv() {
                if !enabled {
                    continue;
                }
                let mut previous = None;
                loop {
                    let bounds = hyprland_ipc_query::<Vec<serde_json::Value>>("j/clients")
                        .and_then(|clients| {
                            clients.into_iter().find(|client| {
                                client["pid"].as_u64() == Some(u64::from(std::process::id()))
                            })
                        })
                        .and_then(|client| serde_json::from_value::<Client>(client).ok())
                        .filter(|client| client.at.len() == 2 && client.size.len() == 2)
                        .map(|client| Rect {
                            x: client.at[0],
                            y: client.at[1],
                            width: client.size[0],
                            height: client.size[1],
                        });
                    if bounds != previous {
                        if let Some(bounds) = bounds {
                            if bounds_tx.send(bounds).is_err() {
                                return;
                            }
                        }
                        previous = bounds;
                    }
                    match control_rx.recv_timeout(Duration::from_millis(33)) {
                        Ok(false) => break,
                        Ok(true) | Err(RecvTimeoutError::Timeout) => {}
                        Err(RecvTimeoutError::Disconnected) => return,
                    }
                }
            }
        })
        .expect("spawn picker bounds watcher");
    (control_tx, bounds_rx)
}

pub fn listen_socket2<F: Fn(&str) + Send + 'static>(callback: F) -> Option<thread::JoinHandle<()>> {
    let his = hyprland_instance_signature()?;
    let uid = rustix::process::getuid().as_raw();
    let sock_path = format!("/run/user/{uid}/hypr/{his}/.socket2.sock");

    thread::Builder::new()
        .name("hypr-socket2".into())
        .spawn(move || {
            use std::io::BufRead;
            loop {
                if let Ok(stream) = UnixStream::connect(&sock_path) {
                    let reader = std::io::BufReader::new(stream);
                    for line in reader.lines() {
                        match line {
                            Ok(msg) => callback(&msg),
                            Err(_) => break,
                        }
                    }
                }
                thread::sleep(Duration::from_millis(500));
            }
        })
        .ok()
}

/// Sends one request to Hyprland's command socket and returns the answer.
pub fn hyprland_ipc_raw(req: &str) -> Option<String> {
    let his = hyprland_instance_signature()?;
    let uid = rustix::process::getuid().as_raw();
    let sock_path = format!("/run/user/{uid}/hypr/{his}/.socket.sock");
    let mut stream = UnixStream::connect(sock_path).ok()?;
    let _ = stream.set_read_timeout(Some(Duration::from_millis(300)));
    let _ = stream.set_write_timeout(Some(Duration::from_millis(300)));
    stream.write_all(req.as_bytes()).ok()?;
    let mut buf = Vec::new();
    stream.read_to_end(&mut buf).ok()?;
    Some(String::from_utf8_lossy(&buf).into_owned())
}

pub fn hyprland_ipc_query<T: for<'de> Deserialize<'de>>(req: &str) -> Option<T> {
    if let Some(parsed) = hyprland_ipc_raw(req).and_then(|buf| serde_json::from_str(&buf).ok()) {
        return Some(parsed);
    }

    let cmd_arg = match req {
        "j/clients" => vec!["clients", "-j"],
        "j/monitors" => vec!["monitors", "-j"],
        "j/activeworkspace" => vec!["activeworkspace", "-j"],
        _ => return None,
    };

    let output = Command::new("hyprctl").args(cmd_arg).output().ok()?;
    if output.status.success() {
        serde_json::from_slice(&output.stdout).ok()
    } else {
        None
    }
}

pub fn query_clients() -> Vec<Client> {
    hyprland_ipc_query::<Vec<Client>>("j/clients")
        .unwrap_or_default()
        .into_iter()
        .filter(|client| client.class != PICKER_APP_ID)
        .collect()
}

pub fn query_monitors() -> Vec<Monitor> {
    hyprland_ipc_query("j/monitors").unwrap_or_default()
}

#[derive(Debug, Clone, Copy, Deserialize)]
pub struct CursorPos {
    pub x: i32,
    pub y: i32,
}

pub fn query_cursor_pos() -> Option<CursorPos> {
    hyprland_ipc_query("j/cursorpos")
}

/// Topmost of `clients` under a global point: floating windows sit above
/// tiled ones, and among those the most recently focused wins.
pub fn window_at_point(x: i32, y: i32, clients: &[Client]) -> Option<&Client> {
    clients
        .iter()
        .filter(|c| {
            c.at.len() == 2
                && c.size.len() == 2
                && x >= c.at[0]
                && x < c.at[0] + c.size[0]
                && y >= c.at[1]
                && y < c.at[1] + c.size[1]
        })
        .min_by_key(|c| (!c.floating, c.focus_history_id.unwrap_or(i64::MAX)))
}

pub fn query_active_workspace() -> Option<ActiveWorkspace> {
    hyprland_ipc_query("j/activeworkspace")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_monitor_with_inactive_special_workspace() {
        let monitors: Vec<Monitor> = serde_json::from_value(serde_json::json!([{
            "id": 0,
            "name": "DP-1",
            "width": 1920,
            "height": 1080,
            "activeWorkspace": { "id": 1, "name": "1" },
            "specialWorkspace": { "address": "", "type": "", "name": "" }
        }]))
        .expect("an inactive special workspace must not discard the monitor list");

        assert_eq!(monitors.len(), 1);
        assert_eq!(monitors[0].active_workspace.as_ref().unwrap().id, 1);
        assert_eq!(monitors[0].special_workspace.as_ref().unwrap().id, 0);
        assert_eq!(
            parse_region("DP-1 100 200 640 480", &monitors).as_deref(),
            Some("region:DP-1@100,200,640,480")
        );
    }

    #[test]
    fn test_parse_window_list() {
        let entries = parse_window_list(
            "42[HC>]firefox[HT>]A tab[HE>]43[HC>]kitty[HT>]shell[HE>]0xabc[HA>]44[HC>]slack[HT>]chat[HE>]102798129481488[HA>]",
        );
        assert_eq!(
            entries,
            vec![
                PortalWindowEntry {
                    id: "42".to_string(),
                    class: "firefox".to_string(),
                    title: "A tab".to_string(),
                    address: None,
                },
                PortalWindowEntry {
                    id: "43".to_string(),
                    class: "kitty".to_string(),
                    title: "shell".to_string(),
                    address: Some("0xabc".to_string()),
                },
                PortalWindowEntry {
                    id: "44".to_string(),
                    class: "slack".to_string(),
                    title: "chat".to_string(),
                    address: Some("0x5d7e8dfdc710".to_string()),
                },
            ]
        );
    }

    #[test]
    fn test_window_to_region() {
        let mon = Monitor {
            id: 0,
            name: "DP-1".into(),
            description: "".into(),
            width: 1920,
            height: 1080,
            x: 0,
            y: 0,
            scale: 1.0,
            focused: true,
            active_workspace: None,
            special_workspace: None,
        };
        let client = Client {
            address: "0x123".into(),
            stable_id: None,
            at: vec![100, 200],
            size: vec![800, 600],
            workspace: Workspace {
                id: 1,
                name: "1".into(),
            },
            title: "Test".into(),
            class: "test".into(),
            initial_class: "test".into(),
            initial_title: "test".into(),
            focus_history_id: None,
            pinned: false,
            floating: false,
            hidden: false,
            mapped: true,
        };
        assert_eq!(
            window_to_region(&client, &[mon]),
            Some("region:DP-1@100,200,800,600".into())
        );
    }

    #[test]
    fn test_client_matching() {
        let entry = PortalWindowEntry {
            id: "42".to_string(),
            class: "firefox".to_string(),
            title: "A tab".to_string(),
            address: None,
        };
        let client = Client {
            address: "0x123".to_string(),
            stable_id: Some(serde_json::json!("42")),
            at: vec![0, 0],
            size: vec![100, 100],
            workspace: Workspace {
                id: 1,
                name: "1".to_string(),
            },
            title: "Different title".to_string(),
            class: "firefox".to_string(),
            initial_class: "firefox".to_string(),
            initial_title: "firefox".to_string(),
            focus_history_id: None,
            pinned: false,
            floating: false,
            hidden: false,
            mapped: true,
        };

        let binding = [client];
        let matched = client_for_entry(&entry, &binding);
        assert!(matched.is_some());
        assert_eq!(matched.unwrap().address, "0x123");
    }

    #[test]
    fn test_client_visibility() {
        let mon1 = Monitor {
            id: 0,
            name: "eDP-1".into(),
            description: "".into(),
            width: 1920,
            height: 1200,
            x: 0,
            y: 0,
            scale: 1.0,
            focused: true,
            active_workspace: Some(Workspace {
                id: 1,
                name: "1".into(),
            }),
            special_workspace: None,
        };
        let mon2 = Monitor {
            id: 1,
            name: "DP-3".into(),
            description: "".into(),
            width: 3440,
            height: 1440,
            x: 1920,
            y: 0,
            scale: 1.0,
            focused: false,
            active_workspace: Some(Workspace {
                id: 2,
                name: "2".into(),
            }),
            special_workspace: None,
        };
        let monitors = [mon1, mon2];

        let visible_client = Client {
            address: "0x1".into(),
            stable_id: None,
            at: vec![100, 100],
            size: vec![200, 200],
            workspace: Workspace {
                id: 1,
                name: "1".into(),
            },
            title: "Term".into(),
            class: "kitty".into(),
            initial_class: "kitty".into(),
            initial_title: "kitty".into(),
            focus_history_id: None,
            pinned: false,
            floating: false,
            hidden: false,
            mapped: true,
        };
        assert!(visible_client.is_visible_on_any_monitor(&monitors));
        assert!(visible_client.is_visible_on_monitor(&monitors[0]));
        assert!(!visible_client.is_visible_on_monitor(&monitors[1]));

        let hidden_workspace_client = Client {
            address: "0x2".into(),
            stable_id: None,
            at: vec![100, 100],
            size: vec![200, 200],
            workspace: Workspace {
                id: 5,
                name: "5".into(),
            },
            title: "Chat".into(),
            class: "slack".into(),
            initial_class: "slack".into(),
            initial_title: "slack".into(),
            focus_history_id: None,
            pinned: false,
            floating: false,
            hidden: false,
            mapped: true,
        };
        assert!(!hidden_workspace_client.is_visible_on_any_monitor(&monitors));
        assert!(!hidden_workspace_client.is_visible_on_monitor(&monitors[0]));
        assert!(!hidden_workspace_client.is_visible_on_monitor(&monitors[1]));

        let pinned_client = Client {
            pinned: true,
            ..hidden_workspace_client
        };
        assert!(pinned_client.is_visible_on_any_monitor(&monitors));
    }
}
