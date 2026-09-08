use std::{
    env, fs,
    io::{Read, Write},
    os::unix::net::UnixStream,
    path::PathBuf,
    process::Command,
    thread,
    time::Duration,
};

use regex::Regex;
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Workspace {
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

pub fn hyprland_ipc_query<T: for<'de> Deserialize<'de>>(req: &str) -> Option<T> {
    if let Some(his) = hyprland_instance_signature() {
        let uid = rustix::process::getuid().as_raw();
        let sock_path = format!("/run/user/{uid}/hypr/{his}/.socket.sock");
        if let Ok(mut stream) = UnixStream::connect(sock_path) {
            let _ = stream.set_read_timeout(Some(Duration::from_millis(300)));
            let _ = stream.set_write_timeout(Some(Duration::from_millis(300)));
            if stream.write_all(req.as_bytes()).is_ok() {
                let mut buf = Vec::new();
                if stream.read_to_end(&mut buf).is_ok() {
                    if let Ok(parsed) = serde_json::from_slice(&buf) {
                        return Some(parsed);
                    }
                }
            }
        }
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
    hyprland_ipc_query("j/clients").unwrap_or_default()
}

pub fn query_monitors() -> Vec<Monitor> {
    hyprland_ipc_query("j/monitors").unwrap_or_default()
}

pub fn query_active_workspace() -> Option<ActiveWorkspace> {
    hyprland_ipc_query("j/activeworkspace")
}

pub fn window_at_point<'a>(x: i32, y: i32, clients: &'a [Client]) -> Option<&'a Client> {
    let mut candidates: Vec<&Client> = clients
        .iter()
        .filter(|c| {
            if c.at.len() == 2 && c.size.len() == 2 {
                let cx = c.at[0];
                let cy = c.at[1];
                let cw = c.size[0];
                let ch = c.size[1];
                x >= cx && x < cx + cw && y >= cy && y < cy + ch
            } else {
                false
            }
        })
        .collect();

    candidates.sort_by_key(|c| c.focus_history_id.unwrap_or(i64::MAX));
    candidates.first().copied()
}

#[cfg(test)]
mod tests {
    use super::*;

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
