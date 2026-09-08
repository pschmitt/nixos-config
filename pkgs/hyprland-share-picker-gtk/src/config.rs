use regex::Regex;
use std::{fs, path::PathBuf};

pub const DEFAULT_HIGHLIGHT_RGBA: (f64, f64, f64, f64) = (0.2314, 0.5098, 0.9647, 1.0);

#[derive(Debug, Clone)]
pub struct PickerConfig {
    pub scale: f32,
    pub jpeg_quality: u8,
    pub refresh_rate: f32,
    pub columns: i32,
    pub highlight_mode: String,
    pub highlight_color: String,
    pub highlight_fill_opacity: f64,
    pub highlight_border: bool,
    pub highlight_border_size: f64,
    pub dim_color: String,
    pub dim_factor: f64,
}

impl Default for PickerConfig {
    fn default() -> Self {
        Self {
            scale: 0.35,
            jpeg_quality: 78,
            refresh_rate: 4.0,
            columns: 1,
            highlight_mode: "highlight".to_string(),
            highlight_color: "rgba(59, 130, 246, 1.0)".to_string(),
            highlight_fill_opacity: 0.22,
            highlight_border: true,
            highlight_border_size: 3.0,
            dim_color: "rgba(0, 0, 0, 1.0)".to_string(),
            dim_factor: 0.5,
        }
    }
}

pub fn picker_config_path() -> PathBuf {
    let config_home = std::env::var_os("XDG_CONFIG_HOME")
        .map(PathBuf::from)
        .unwrap_or_else(|| {
            let home = std::env::var_os("HOME")
                .map(PathBuf::from)
                .unwrap_or_default();
            home.join(".config")
        });
    config_home.join("hypr").join("xdph-picker-gtk.conf")
}

pub fn parse_picker_config(content: &str) -> PickerConfig {
    let mut config = PickerConfig::default();
    let re = Regex::new(
        r"(?m)^\s*(scale|jpeg_quality|refresh_rate|columns|mode|color|fill_opacity|border_size|border|dim_color|dim_factor)\s*=\s*(.+?)\s*$"
    ).unwrap();

    for cap in re.captures_iter(content) {
        let key = cap[1].trim();
        let val = cap[2].trim();

        match key {
            "scale" => {
                if let Ok(v) = val.parse::<f32>() {
                    if (0.1..=1.0).contains(&v) {
                        config.scale = v;
                    }
                }
            }
            "refresh_rate" => {
                if let Ok(v) = val.parse::<f32>() {
                    if (0.5..=60.0).contains(&v) {
                        config.refresh_rate = v;
                    }
                }
            }
            "highlight_fill_opacity" | "fill_opacity" => {
                if let Ok(v) = val.parse::<f64>() {
                    if (0.0..=1.0).contains(&v) {
                        config.highlight_fill_opacity = v;
                    }
                }
            }
            "dim_factor" => {
                if let Ok(v) = val.parse::<f64>() {
                    if (0.0..=1.0).contains(&v) {
                        config.dim_factor = v;
                    }
                }
            }
            "jpeg_quality" => {
                if let Ok(v) = val.parse::<u8>() {
                    if (1..=100).contains(&v) {
                        config.jpeg_quality = v;
                    }
                }
            }
            "columns" => {
                if let Ok(v) = val.parse::<i32>() {
                    if (1..=12).contains(&v) {
                        config.columns = v;
                    }
                }
            }
            "highlight_border_size" | "border_size" => {
                if let Ok(v) = val.parse::<f64>() {
                    if (1.0..=30.0).contains(&v) {
                        config.highlight_border_size = v;
                    }
                }
            }
            "highlight_border" | "border" => match val.to_lowercase().as_str() {
                "true" | "yes" | "on" | "1" => config.highlight_border = true,
                "false" | "no" | "off" | "0" => config.highlight_border = false,
                _ => config.highlight_border = true,
            },
            "highlight_mode" | "mode" => {
                let m = val.to_lowercase();
                if m == "highlight" || m == "dim" {
                    config.highlight_mode = m;
                }
            }
            "highlight_color" | "color" => {
                if !val.is_empty() {
                    config.highlight_color = val.to_string();
                }
            }
            "dim_color" => {
                if !val.is_empty() {
                    config.dim_color = val.to_string();
                }
            }
            _ => {}
        }
    }

    config
}

pub fn load_config() -> PickerConfig {
    let path = picker_config_path();
    if let Ok(content) = fs::read_to_string(&path) {
        parse_picker_config(&content)
    } else {
        PickerConfig::default()
    }
}

pub fn parse_rgba_color(value: &str, default: (f64, f64, f64, f64)) -> (f64, f64, f64, f64) {
    let value = value.trim();
    if value.starts_with('#') {
        let hex = value.trim_start_matches('#');
        match hex.len() {
            3 => {
                let r = u8::from_str_radix(&hex[0..1].repeat(2), 16).ok();
                let g = u8::from_str_radix(&hex[1..2].repeat(2), 16).ok();
                let b = u8::from_str_radix(&hex[2..3].repeat(2), 16).ok();
                if let (Some(r), Some(g), Some(b)) = (r, g, b) {
                    return (r as f64 / 255.0, g as f64 / 255.0, b as f64 / 255.0, 1.0);
                }
            }
            6 => {
                let r = u8::from_str_radix(&hex[0..2], 16).ok();
                let g = u8::from_str_radix(&hex[2..4], 16).ok();
                let b = u8::from_str_radix(&hex[4..6], 16).ok();
                if let (Some(r), Some(g), Some(b)) = (r, g, b) {
                    return (r as f64 / 255.0, g as f64 / 255.0, b as f64 / 255.0, 1.0);
                }
            }
            8 => {
                let r = u8::from_str_radix(&hex[0..2], 16).ok();
                let g = u8::from_str_radix(&hex[2..4], 16).ok();
                let b = u8::from_str_radix(&hex[4..6], 16).ok();
                let a = u8::from_str_radix(&hex[6..8], 16).ok();
                if let (Some(r), Some(g), Some(b), Some(a)) = (r, g, b, a) {
                    return (
                        r as f64 / 255.0,
                        g as f64 / 255.0,
                        b as f64 / 255.0,
                        a as f64 / 255.0,
                    );
                }
            }
            _ => {}
        }
        return default;
    }

    let rgba_re = Regex::new(
        r"^rgba?\s*\(\s*([\d.]+)\s*,\s*([\d.]+)\s*,\s*([\d.]+)(?:\s*,\s*([\d.]+))?\s*\)$",
    )
    .unwrap();

    if let Some(cap) = rgba_re.captures(value) {
        if let (Ok(r_val), Ok(g_val), Ok(b_val)) = (
            cap[1].parse::<f64>(),
            cap[2].parse::<f64>(),
            cap[3].parse::<f64>(),
        ) {
            let r = if r_val > 1.0 { r_val / 255.0 } else { r_val };
            let g = if g_val > 1.0 { g_val / 255.0 } else { g_val };
            let b = if b_val > 1.0 { b_val / 255.0 } else { b_val };
            let a = cap
                .get(4)
                .and_then(|m| m.as_str().parse::<f64>().ok())
                .unwrap_or(1.0);
            return (r, g, b, a);
        }
    }

    default
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_parse_config() {
        let conf = parse_picker_config(
            "columns = 3\npreview {\n  scale = 0.5\n  jpeg_quality = 90\n  refresh_rate = 8\n}",
        );
        assert_eq!(conf.columns, 3);
        assert_eq!(conf.scale, 0.5);
        assert_eq!(conf.jpeg_quality, 90);
        assert_eq!(conf.refresh_rate, 8.0);

        let highlight_section = parse_picker_config(
            "highlight {\n  mode = dim\n  color = #a855f7\n  fill_opacity = 0.4\n  border = false\n  border_size = 8\n  dim_color = #101010\n  dim_factor = 0.7\n}",
        );
        assert_eq!(highlight_section.highlight_mode, "dim");
        assert_eq!(highlight_section.highlight_color, "#a855f7");
        assert_eq!(highlight_section.highlight_fill_opacity, 0.4);
        assert!(!highlight_section.highlight_border);
        assert_eq!(highlight_section.highlight_border_size, 8.0);
        assert_eq!(highlight_section.dim_color, "#101010");
        assert_eq!(highlight_section.dim_factor, 0.7);
    }

    #[test]
    fn test_parse_color() {
        let (r, g, b, a) = parse_rgba_color("#a855f7", DEFAULT_HIGHLIGHT_RGBA);
        assert!((r - 0.6588).abs() < 0.01);
        assert!((g - 0.3333).abs() < 0.01);
        assert!((b - 0.9686).abs() < 0.01);
        assert_eq!(a, 1.0);
    }
}
