use std::{
    collections::HashMap,
    env, fs,
    path::{Path, PathBuf},
};

use gtk4::{Image, Widget, gdk, prelude::*};

#[allow(dead_code)]
#[derive(Debug, Clone)]
pub struct DesktopApp {
    pub id: String,
    pub name: String,
    pub wm_class: Option<String>,
    pub icon: Option<String>,
}

#[derive(Debug, Default, Clone)]
pub struct DesktopRegistry {
    apps: Vec<DesktopApp>,
    by_wm_class: HashMap<String, usize>,
    by_id: HashMap<String, usize>,
}

impl DesktopRegistry {
    pub fn new() -> Self {
        let mut registry = Self::default();
        registry.scan_desktop_dirs();
        registry
    }

    fn scan_desktop_dirs(&mut self) {
        let mut search_dirs = Vec::new();

        // 1. $XDG_DATA_HOME/applications or ~/.local/share/applications
        let data_home = env::var_os("XDG_DATA_HOME")
            .map(PathBuf::from)
            .unwrap_or_else(|| {
                let home = env::var_os("HOME").map(PathBuf::from).unwrap_or_default();
                home.join(".local").join("share")
            });
        search_dirs.push(data_home.join("applications"));

        // 2. $XDG_DATA_DIRS
        if let Some(dirs) = env::var_os("XDG_DATA_DIRS") {
            for part in env::split_paths(&dirs) {
                search_dirs.push(part.join("applications"));
            }
        }

        // 3. Fallback standard and NixOS paths
        if let Ok(user) = env::var("USER") {
            search_dirs.push(PathBuf::from(format!(
                "/etc/profiles/per-user/{user}/share/applications"
            )));
        }
        search_dirs.push(PathBuf::from("/run/current-system/sw/share/applications"));
        if let Some(home) = env::var_os("HOME").map(PathBuf::from) {
            search_dirs.push(home.join(".nix-profile").join("share").join("applications"));
            search_dirs.push(
                home.join(".local")
                    .join("share")
                    .join("flatpak")
                    .join("exports")
                    .join("share")
                    .join("applications"),
            );
        }
        search_dirs.push(PathBuf::from("/var/lib/flatpak/exports/share/applications"));
        search_dirs.push(PathBuf::from("/usr/local/share/applications"));
        search_dirs.push(PathBuf::from("/usr/share/applications"));

        let mut seen_paths = std::collections::HashSet::new();

        for dir in search_dirs {
            if !dir.is_dir() {
                continue;
            }
            if let Ok(read_dir) = fs::read_dir(dir) {
                for entry in read_dir.flatten() {
                    let path = entry.path();
                    if path.extension().and_then(|s| s.to_str()) == Some("desktop") {
                        if seen_paths.insert(path.clone()) {
                            if let Some(app) = Self::parse_desktop_file(&path) {
                                self.add_app(app);
                            }
                        }
                    }
                }
            }
        }
    }

    fn parse_desktop_file(path: &Path) -> Option<DesktopApp> {
        let content = fs::read_to_string(path).ok()?;
        let file_stem = path.file_stem()?.to_str()?.to_string();

        let mut in_desktop_entry = false;
        let mut name = None;
        let mut wm_class = None;
        let mut icon = None;
        let mut is_app = true;

        for line in content.lines() {
            let line = line.trim();
            if line == "[Desktop Entry]" {
                in_desktop_entry = true;
                continue;
            }
            if line.starts_with('[') && in_desktop_entry {
                break;
            }
            if in_desktop_entry {
                if let Some((k, v)) = line.split_once('=') {
                    let k = k.trim();
                    let v = v.trim();
                    match k {
                        "Type" => {
                            if v != "Application" {
                                is_app = false;
                            }
                        }
                        "Name" if name.is_none() => {
                            name = Some(v.to_string());
                        }
                        "StartupWMClass" if wm_class.is_none() => {
                            wm_class = Some(v.to_string());
                        }
                        "Icon" if icon.is_none() => {
                            icon = Some(v.to_string());
                        }
                        _ => {}
                    }
                }
            }
        }

        if !is_app {
            return None;
        }

        Some(DesktopApp {
            id: file_stem,
            name: name.unwrap_or_default(),
            wm_class,
            icon,
        })
    }

    fn add_app(&mut self, app: DesktopApp) {
        let idx = self.apps.len();
        if let Some(ref wmc) = app.wm_class {
            self.by_wm_class.entry(wmc.to_lowercase()).or_insert(idx);
        }
        self.by_id.entry(app.id.to_lowercase()).or_insert(idx);
        self.apps.push(app);
    }

    pub fn find_icon_for_class(&self, class: &str, initial_class: &str) -> Option<String> {
        // 1. Match class against StartupWMClass
        if let Some(&idx) = self.by_wm_class.get(&class.to_lowercase()) {
            if let Some(ref icon) = self.apps[idx].icon {
                if !icon.is_empty() {
                    return Some(icon.clone());
                }
            }
        }

        // 2. Match initial_class against StartupWMClass
        if !initial_class.is_empty() && initial_class != class {
            if let Some(&idx) = self.by_wm_class.get(&initial_class.to_lowercase()) {
                if let Some(ref icon) = self.apps[idx].icon {
                    if !icon.is_empty() {
                        return Some(icon.clone());
                    }
                }
            }
        }

        // 3. Match class against desktop ID
        if let Some(&idx) = self.by_id.get(&class.to_lowercase()) {
            if let Some(ref icon) = self.apps[idx].icon {
                if !icon.is_empty() {
                    return Some(icon.clone());
                }
            }
        }

        // 4. Match initial_class against desktop ID
        if !initial_class.is_empty() && initial_class != class {
            if let Some(&idx) = self.by_id.get(&initial_class.to_lowercase()) {
                if let Some(ref icon) = self.apps[idx].icon {
                    if !icon.is_empty() {
                        return Some(icon.clone());
                    }
                }
            }
        }

        // 5. Try prefixes by trimming trailing '-' or '_' segments
        // (e.g. "kitty-scratchpad" -> "kitty", "test-app-child" -> "test-app" then "test")
        for cls in [class, initial_class] {
            let mut cur: &str = cls;
            while let Some(idx) = cur.rfind(|c| c == '-' || c == '_') {
                let prefix = &cur[..idx];
                if prefix.is_empty() {
                    break;
                }
                if let Some(&app_idx) = self.by_wm_class.get(&prefix.to_lowercase()) {
                    if let Some(ref icon) = self.apps[app_idx].icon {
                        if !icon.is_empty() {
                            return Some(icon.clone());
                        }
                    }
                }
                if let Some(&app_idx) = self.by_id.get(&prefix.to_lowercase()) {
                    if let Some(ref icon) = self.apps[app_idx].icon {
                        if !icon.is_empty() {
                            return Some(icon.clone());
                        }
                    }
                }
                cur = prefix;
            }
        }

        // 6. Try last segment of reverse-domain class (e.g. "org.gnome.Nautilus" -> "Nautilus")
        for cls in [class, initial_class] {
            if let Some(last) = cls.rsplit('.').next() {
                if last != cls && !last.is_empty() {
                    if let Some(&idx) = self.by_wm_class.get(&last.to_lowercase()) {
                        if let Some(ref icon) = self.apps[idx].icon {
                            if !icon.is_empty() {
                                return Some(icon.clone());
                            }
                        }
                    }
                    if let Some(&idx) = self.by_id.get(&last.to_lowercase()) {
                        if let Some(ref icon) = self.apps[idx].icon {
                            if !icon.is_empty() {
                                return Some(icon.clone());
                            }
                        }
                    }
                }
            }
        }

        None
    }
}

fn make_icon_image_from_file(path: &Path, pixel_size: i32) -> Widget {
    let file = gio::File::for_path(path);
    let gicon = gio::FileIcon::new(&file);
    let img = Image::from_gicon(&gicon);
    img.set_pixel_size(pixel_size);
    img.set_size_request(pixel_size, pixel_size);
    img.set_halign(gtk4::Align::Center);
    img.set_valign(gtk4::Align::Center);
    img.set_hexpand(false);
    img.set_vexpand(false);
    img.add_css_class("app-icon");
    img.upcast::<Widget>()
}

fn make_icon_image_from_name(icon_name: &str, pixel_size: i32) -> Widget {
    let img = Image::from_icon_name(icon_name);
    img.set_pixel_size(pixel_size);
    img.set_size_request(pixel_size, pixel_size);
    img.set_halign(gtk4::Align::Center);
    img.set_valign(gtk4::Align::Center);
    img.set_hexpand(false);
    img.set_vexpand(false);
    img.add_css_class("app-icon");
    img.upcast::<Widget>()
}

pub fn create_app_icon(
    registry: &DesktopRegistry,
    class: &str,
    initial_class: &str,
    pixel_size: i32,
) -> Widget {
    let resolved_icon = registry.find_icon_for_class(class, initial_class);

    // 1. If it's an absolute path to an existing file (or with extension)
    if let Some(ref icon_val) = resolved_icon {
        let p = Path::new(icon_val);
        if p.is_absolute() {
            if p.exists() {
                return make_icon_image_from_file(p, pixel_size);
            }
            for ext in ["png", "svg", "xpm"] {
                let pe = p.with_extension(ext);
                if pe.exists() {
                    return make_icon_image_from_file(&pe, pixel_size);
                }
            }
        }
    }

    let display = gdk::Display::default();
    let theme = display.as_ref().map(gtk4::IconTheme::for_display);

    // 2. Check resolved icon in theme
    if let Some(ref icon_val) = resolved_icon {
        let name = icon_val
            .strip_suffix(".png")
            .or_else(|| icon_val.strip_suffix(".svg"))
            .or_else(|| icon_val.strip_suffix(".xpm"))
            .unwrap_or(icon_val);

        if let Some(ref th) = theme {
            for candidate in [name, &name.to_lowercase()] {
                if th.has_icon(candidate) {
                    return make_icon_image_from_name(candidate, pixel_size);
                }
            }
        } else {
            return make_icon_image_from_name(name, pixel_size);
        }

        // 2b. Check pixmaps directories
        let user = env::var("USER").unwrap_or_default();
        let pix_dirs = [
            format!("/etc/profiles/per-user/{user}/share/pixmaps"),
            "/run/current-system/sw/share/pixmaps".to_string(),
            "/usr/share/pixmaps".to_string(),
        ];
        for pix_dir in &pix_dirs {
            let base = Path::new(pix_dir).join(icon_val);
            if base.exists() {
                return make_icon_image_from_file(&base, pixel_size);
            }
            for ext in ["png", "svg", "xpm"] {
                let pe = base.with_extension(ext);
                if pe.exists() {
                    return make_icon_image_from_file(&pe, pixel_size);
                }
            }
        }
    }

    // 3. Check class and initial_class directly in theme
    if let Some(ref th) = theme {
        for candidate in [
            class,
            &class.to_lowercase(),
            initial_class,
            &initial_class.to_lowercase(),
        ] {
            if !candidate.is_empty() && th.has_icon(candidate) {
                return make_icon_image_from_name(candidate, pixel_size);
            }
        }
    }

    // 4. Fallback generic icon
    make_icon_image_from_name("application-x-executable-symbolic", pixel_size)
}

pub fn create_themed_icon(icon_name: &str, pixel_size: i32) -> Widget {
    make_icon_image_from_name(icon_name, pixel_size)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_parse_desktop_entry() {
        let tmp_dir = std::env::temp_dir().join("test_desktop_entry");
        let _ = fs::create_dir_all(&tmp_dir);
        let test_file = tmp_dir.join("test-app.desktop");
        fs::write(
            &test_file,
            "[Desktop Entry]\nType=Application\nName=Test App\nStartupWMClass=test-app-class\nIcon=test-icon\n",
        )
        .unwrap();

        let app = DesktopRegistry::parse_desktop_file(&test_file).expect("parse desktop file");
        assert_eq!(app.id, "test-app");
        assert_eq!(app.name, "Test App");
        assert_eq!(app.wm_class.as_deref(), Some("test-app-class"));
        assert_eq!(app.icon.as_deref(), Some("test-icon"));

        let mut reg = DesktopRegistry::default();
        reg.add_app(app);

        assert_eq!(
            reg.find_icon_for_class("test-app-class", ""),
            Some("test-icon".into())
        );
        assert_eq!(
            reg.find_icon_for_class("test-app", ""),
            Some("test-icon".into())
        );
        assert_eq!(
            reg.find_icon_for_class("test-app-child", ""),
            Some("test-icon".into())
        );

        let _ = fs::remove_file(test_file);
    }

    #[test]
    fn test_icon_dimensions() {
        if gtk4::init().is_err() {
            return;
        }
        let reg = DesktopRegistry::new();
        let icon_widget = create_app_icon(&reg, "kitty-tmux", "", 32);
        let (min, nat) = icon_widget.preferred_size();
        assert_eq!(min.width(), 32);
        assert_eq!(min.height(), 32);
        assert_eq!(nat.width(), 32);
        assert_eq!(nat.height(), 32);

        let themed = create_themed_icon("video-display-symbolic", 32);
        let (min, nat) = themed.preferred_size();
        assert_eq!(min.width(), 32);
        assert_eq!(min.height(), 32);
        assert_eq!(nat.width(), 32);
        assert_eq!(nat.height(), 32);

        let scroll = gtk4::ScrolledWindow::new();
        scroll.set_policy(gtk4::PolicyType::Never, gtk4::PolicyType::Never);
        scroll.set_size_request(-1, 170);

        let pic = gtk4::Picture::new();
        pic.set_can_shrink(true);
        pic.set_content_fit(gtk4::ContentFit::Cover);
        scroll.set_child(Some(&pic));

        let bytes = vec![0u8; 800 * 600 * 4];
        let tex = gdk::MemoryTexture::new(
            800,
            600,
            gdk::MemoryFormat::R8g8b8a8,
            &glib::Bytes::from(&bytes),
            800 * 4,
        );
        pic.set_paintable(Some(&tex));

        let (min_h, nat_h, _, _) = scroll.measure(gtk4::Orientation::Vertical, 530);
        assert_eq!(min_h, 170);
        assert_eq!(nat_h, 170);
    }
}
