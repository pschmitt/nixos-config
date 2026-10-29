//! Marks the hovered or selected window through Hyprland's own window
//! properties: everything around it is dimmed and its border recolored.
//! The compositor draws both, so they follow the window's rounded corners
//! and animations, which a layer-shell overlay cannot.
//!
//! Every property is put back to the value it had before, also on exit:
//! unlike the overlay, these outlive the picker process.

use std::sync::Mutex;

use crate::{
    config::{DEFAULT_HIGHLIGHT_RGBA, PickerConfig, parse_rgba_color},
    hyprland::hyprland_ipc_raw,
};

/// Window currently decorated, with the values to restore.
static DECORATED: Mutex<Option<Decorated>> = Mutex::new(None);

struct Decorated {
    address: String,
    restore: Vec<(&'static str, String)>,
}

/// Property values that mark a window in `color` for the given picker
/// config.
pub fn props_for(config: &PickerConfig, color: &str) -> Vec<(&'static str, String)> {
    let (r, g, b, _) = parse_rgba_color(color, DEFAULT_HIGHLIGHT_RGBA);
    let byte = |v: f64| (v.clamp(0.0, 1.0) * 255.0).round() as u8;
    let color = format!("rgba({:02x}{:02x}{:02x}ff)", byte(r), byte(g), byte(b));
    let mut props = vec![
        ("active_border_color", color.clone()),
        ("inactive_border_color", color),
        (
            "border_size",
            (config.highlight_border_size.round().max(1.0) as u32).to_string(),
        ),
    ];
    if config.highlight_mode == "dim" {
        props.push(("dim_around", "1".into()));
    }
    props
}

/// Decorates the window at `address`, restoring any other one first.
/// Does nothing when that window is already decorated.
pub fn decorate(address: &str, props: &[(&'static str, String)]) {
    let Ok(mut current) = DECORATED.lock() else {
        return;
    };
    if current.as_ref().is_some_and(|d| d.address == address) {
        return;
    }
    restore_locked(&mut current);
    let restore = props
        .iter()
        .map(|(prop, _)| (*prop, restore_value(prop, &get_prop(address, prop))))
        .collect();
    for (prop, value) in props {
        set_prop(address, prop, value);
    }
    *current = Some(Decorated {
        address: address.to_string(),
        restore,
    });
}

/// Puts the decorated window, if any, back the way it was.
pub fn restore() {
    if let Ok(mut current) = DECORATED.lock() {
        restore_locked(&mut current);
    }
}

fn restore_locked(current: &mut Option<Decorated>) {
    if let Some(decorated) = current.take() {
        for (prop, value) in &decorated.restore {
            set_prop(&decorated.address, prop, value);
        }
    }
}

fn get_prop(address: &str, prop: &str) -> String {
    hyprland_ipc_raw(&format!("/getprop address:{address} {prop}"))
        .unwrap_or_default()
        .trim()
        .to_string()
}

fn set_prop(address: &str, prop: &str, value: &str) {
    let _ = hyprland_ipc_raw(&format!(
        "/dispatch hl.dsp.window.set_prop({{ window = 'address:{address}', prop = '{prop}', value = '{value}' }})"
    ));
}

/// Turns a `getprop` answer into a value `set_prop` accepts. Colors come
/// back as `AARRGGBB` tokens plus an angle and go in as `rgba(RRGGBBAA)`.
fn restore_value(prop: &str, current: &str) -> String {
    match prop {
        "dim_around" => if current == "true" { "1" } else { "unset" }.into(),
        p if p.ends_with("_color") => {
            let mut colors = Vec::new();
            let mut angle = None;
            for token in current.split_whitespace() {
                if token.len() == 8 && token.chars().all(|c| c.is_ascii_hexdigit()) {
                    colors.push(format!("rgba({}{})", &token[2..], &token[..2]));
                } else if token.ends_with("deg") {
                    angle = Some(token);
                }
            }
            if colors.is_empty() {
                return "unset".into();
            }
            colors.extend(angle.map(str::to_string));
            colors.join(" ")
        }
        _ if current.is_empty() => "unset".into(),
        _ => current.to_string(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn restores_gradient_colors() {
        assert_eq!(
            restore_value("active_border_color", "ff8aa4c5 0deg"),
            "rgba(8aa4c5ff) 0deg"
        );
        assert_eq!(
            restore_value("active_border_color", "ff112233 80445566 45deg"),
            "rgba(112233ff) rgba(44556680) 45deg"
        );
        assert_eq!(restore_value("inactive_border_color", "0deg"), "unset");
    }

    #[test]
    fn restores_flags_and_numbers() {
        assert_eq!(restore_value("dim_around", "false"), "unset");
        assert_eq!(restore_value("dim_around", "true"), "1");
        assert_eq!(restore_value("border_size", "2"), "2");
    }
}
