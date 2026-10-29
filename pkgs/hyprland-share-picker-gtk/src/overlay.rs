use std::{
    cell::{Cell, RefCell},
    collections::HashMap,
    rc::Rc,
    sync::mpsc::{Receiver, Sender},
};

use gtk4::{DrawingArea, Window, cairo, gdk, prelude::*};
use gtk4_layer_shell::{Edge, KeyboardMode, Layer, LayerShell};

use crate::{
    config::{DEFAULT_HIGHLIGHT_RGBA, PickerConfig, parse_rgba_color},
    decoration,
    hyprland::{
        Client, Monitor, Rect, RegionDetails, hyprland_ipc_raw, spawn_picker_bounds_watcher,
    },
};

/// Matches the picker's CSS border-radius and its Hyprland rounding rule.
const PICKER_RADIUS: f64 = 16.0;

/// Hyprland's window corner radius, so the cut-out matches the window.
fn query_window_rounding() -> f64 {
    hyprland_ipc_raw("j/getoption decoration:rounding")
        .and_then(|raw| serde_json::from_str::<serde_json::Value>(&raw).ok())
        .and_then(|v| v.get("int").and_then(|i| i.as_f64()))
        .unwrap_or(0.0)
}

fn rounded_rect(cr: &cairo::Context, x: f64, y: f64, w: f64, h: f64, r: f64) {
    use std::f64::consts::{FRAC_PI_2, PI};
    cr.new_sub_path();
    cr.arc(x + w - r, y + r, r, -FRAC_PI_2, 0.0);
    cr.arc(x + w - r, y + h - r, r, 0.0, FRAC_PI_2);
    cr.arc(x + r, y + h - r, r, FRAC_PI_2, PI);
    cr.arc(x + r, y + r, r, PI, 3.0 * FRAC_PI_2);
    cr.close_path();
}

struct MonitorOverlay {
    window: Window,
    drawing_area: DrawingArea,
    geom: gdk::Rectangle,
    state: Rc<RefCell<OverlayState>>,
}

struct OverlayState {
    active_rect: Option<Rect>,
    picker_rect: Option<Rect>,
    dim_all: bool,
    /// Set while marking a window: Hyprland draws its border, so the
    /// overlay only dims around a cut-out with this corner radius.
    window_radius: Option<f64>,
}

pub struct OverlayHighlighter {
    tracking: Cell<bool>,
    picker_bounds: Cell<Option<Rect>>,
    tracking_tx: Sender<bool>,
    bounds_rx: Receiver<Rect>,
    overlays: HashMap<String, MonitorOverlay>,
    config: PickerConfig,
    window_props: decoration::Props,
    window_rounding: f64,
    r: f64,
    g: f64,
    b: f64,
    fill_alpha: f64,
    border_alpha: f64,
    draw_border: bool,
    border_width: f64,
    dim_r: f64,
    dim_g: f64,
    dim_b: f64,
    dim_alpha: f64,
}

impl OverlayHighlighter {
    pub fn new(config: &PickerConfig) -> Option<Self> {
        if !gtk4_layer_shell::is_supported() {
            return None;
        }
        let display = gdk::Display::default()?;
        let (tracking_tx, bounds_rx) = spawn_picker_bounds_watcher();
        let (r, g, b, _) = parse_rgba_color(&config.highlight_color, DEFAULT_HIGHLIGHT_RGBA);
        let (dim_r, dim_g, dim_b, _) = parse_rgba_color(&config.dim_color, (0.0, 0.0, 0.0, 1.0));

        let mut highlighter = Self {
            tracking: Cell::new(false),
            picker_bounds: Cell::new(None),
            tracking_tx,
            bounds_rx,
            overlays: HashMap::new(),
            config: config.clone(),
            window_props: decoration::props_for(config, &config.highlight_color),
            window_rounding: query_window_rounding(),
            r,
            g,
            b,
            fill_alpha: config.highlight_fill_opacity,
            border_alpha: 0.95,
            draw_border: config.highlight_border,
            border_width: config.highlight_border_size,
            dim_r,
            dim_g,
            dim_b,
            dim_alpha: config.dim_factor,
        };

        let monitors = display.monitors();
        for i in 0..monitors.n_items() {
            if let Some(mon) = monitors.item(i).and_downcast::<gdk::Monitor>() {
                if let Some(connector) = mon.connector() {
                    let geom = mon.geometry();
                    highlighter.create_monitor_overlay(&connector, &mon, geom);
                }
            }
        }

        Some(highlighter)
    }

    fn create_monitor_overlay(
        &mut self,
        connector: &str,
        mon: &gdk::Monitor,
        geom: gdk::Rectangle,
    ) {
        let win = Window::new();
        win.add_css_class("overlay-highlighter");
        win.init_layer_shell();
        win.set_layer(Layer::Top);
        win.set_keyboard_mode(KeyboardMode::None);
        win.set_exclusive_zone(-1);
        win.set_namespace("hyprland-share-picker-highlight");
        win.set_anchor(Edge::Top, true);
        win.set_anchor(Edge::Bottom, true);
        win.set_anchor(Edge::Left, true);
        win.set_anchor(Edge::Right, true);
        win.set_monitor(mon);

        let state = Rc::new(RefCell::new(OverlayState {
            active_rect: None,
            picker_rect: None,
            dim_all: false,
            window_radius: None,
        }));

        let area = DrawingArea::new();
        let state_clone = state.clone();

        let mode = self.config.highlight_mode.clone();
        let r = self.r;
        let g = self.g;
        let b = self.b;
        let fill_alpha = self.fill_alpha;
        let border_alpha = self.border_alpha;
        let draw_border = self.draw_border;
        let border_width = self.border_width;
        let dim_r = self.dim_r;
        let dim_g = self.dim_g;
        let dim_b = self.dim_b;
        let dim_alpha = self.dim_alpha;

        area.set_draw_func(move |_area, cr, width, height| {
            let s = state_clone.borrow();
            let rect = s.active_rect;
            let dim_all = s.dim_all;
            let window_radius = s.window_radius;

            let _ = cr.save();
            cr.set_operator(cairo::Operator::Clear);
            let _ = cr.paint();
            let _ = cr.restore();

            if rect.is_none() && !dim_all {
                return;
            }

            if mode == "dim" {
                let _ = cr.save();
                cr.rectangle(0.0, 0.0, width as f64, height as f64);
                if let Some(target_rect) = rect {
                    let (x, y, w, h) = (
                        target_rect.x as f64,
                        target_rect.y as f64,
                        target_rect.width as f64,
                        target_rect.height as f64,
                    );
                    match window_radius {
                        Some(radius) => {
                            rounded_rect(cr, x, y, w, h, radius.min(w / 2.0).min(h / 2.0))
                        }
                        None => cr.rectangle(x, y, w, h),
                    }
                    cr.set_fill_rule(cairo::FillRule::EvenOdd);
                }
                cr.set_source_rgba(dim_r, dim_g, dim_b, dim_alpha);
                let _ = cr.fill();
                let _ = cr.restore();
            }

            if let Some(target_rect) = rect.filter(|_| window_radius.is_none()) {
                let _ = cr.save();
                cr.rectangle(
                    target_rect.x as f64,
                    target_rect.y as f64,
                    target_rect.width as f64,
                    target_rect.height as f64,
                );
                cr.set_source_rgba(r, g, b, fill_alpha);
                let _ = cr.fill();
                let _ = cr.restore();

                if draw_border {
                    let _ = cr.save();
                    cr.rectangle(
                        target_rect.x as f64,
                        target_rect.y as f64,
                        target_rect.width as f64,
                        target_rect.height as f64,
                    );
                    cr.set_source_rgba(r, g, b, border_alpha);
                    cr.set_line_width(border_width);
                    let _ = cr.stroke();
                    let _ = cr.restore();
                }
            }
            // Keep the regular picker window clear of the layer-shell tint.
            if let Some(picker) = s.picker_rect {
                let _ = cr.save();
                cr.set_operator(cairo::Operator::Clear);
                rounded_rect(
                    cr,
                    picker.x as f64,
                    picker.y as f64,
                    picker.width as f64,
                    picker.height as f64,
                    PICKER_RADIUS,
                );
                let _ = cr.fill();
                let _ = cr.restore();
            }
        });

        win.set_child(Some(&area));

        // Pass all mouse/input events straight through to windows beneath
        win.connect_realize(|w| {
            if let Some(surface) = w.surface() {
                surface.set_input_region(&cairo::Region::create());
            }
        });
        win.connect_map(|w| {
            if let Some(surface) = w.surface() {
                surface.set_input_region(&cairo::Region::create());
            }
        });

        self.overlays.insert(
            connector.to_string(),
            MonitorOverlay {
                window: win,
                drawing_area: area,
                geom,
                state,
            },
        );
    }

    pub fn highlight_screen(&self, monitor_name: &str) {
        decoration::restore();
        for (connector, entry) in &self.overlays {
            if connector == monitor_name {
                let rect = Rect {
                    x: 0,
                    y: 0,
                    width: entry.geom.width(),
                    height: entry.geom.height(),
                };
                self.show_entry(entry, Some(rect), false);
            } else {
                self.show_entry(entry, None, true);
            }
        }
    }

    pub fn highlight_region(&self, region: &RegionDetails) {
        decoration::restore();
        for (connector, entry) in &self.overlays {
            if connector == &region.output {
                let rect = Rect {
                    x: region.x,
                    y: region.y,
                    width: region.width as i32,
                    height: region.height as i32,
                };
                self.show_entry(entry, Some(rect), false);
            } else {
                self.show_entry(entry, None, true);
            }
        }
    }

    /// Marks a window next to the picker: Hyprland draws its border, the
    /// overlay dims everything else. `dim_around` cannot do the dimming:
    /// it misses windows Hyprland draws after the target.
    pub fn highlight_window(&self, client: &Client, monitors: &[Monitor]) {
        self.mark_window(client, monitors, false);
    }

    /// Same as `highlight_window` while the picker is hidden, as in the
    /// direct window pick: nothing to keep clear, so no bounds to wait for.
    pub fn highlight_window_standalone(&self, client: Option<&Client>, monitors: &[Monitor]) {
        self.picker_bounds.set(None);
        for entry in self.overlays.values() {
            entry.state.borrow_mut().picker_rect = None;
        }
        match client {
            Some(client) => self.mark_window(client, monitors, true),
            None => self.clear(),
        }
    }

    fn mark_window(&self, client: &Client, monitors: &[Monitor], standalone: bool) {
        if client.at.len() != 2 || client.size.len() != 2 {
            self.clear();
            return;
        }

        if !client.is_visible_on_any_monitor(monitors) {
            self.clear();
            return;
        }

        decoration::decorate(&client.address, &self.window_props);

        // Keep Hyprland's border, drawn just outside the window, clear too.
        let pad = self.border_width.round() as i32;
        let global_rect = Rect {
            x: client.at[0] - pad,
            y: client.at[1] - pad,
            width: client.size[0] + 2 * pad,
            height: client.size[1] + 2 * pad,
        };
        let radius = self.window_rounding + pad as f64;

        for (connector, entry) in &self.overlays {
            let target = monitors
                .iter()
                .find(|m| &m.name == connector)
                .filter(|m| client.is_visible_on_monitor(m))
                .and_then(|_| self.relative_rect(global_rect, entry.geom));
            {
                let mut s = entry.state.borrow_mut();
                s.active_rect = target;
                s.dim_all = target.is_none();
                s.window_radius = Some(radius);
            }
            self.set_tracking(!standalone);
            let visible = if standalone {
                self.config.highlight_mode == "dim"
            } else {
                self.picker_bounds.get().is_some()
            };
            entry.window.set_visible(visible);
            entry.drawing_area.queue_draw();
        }
    }

    pub fn clear(&self) {
        decoration::restore();
        self.set_tracking(false);
        self.picker_bounds.set(None);
        for entry in self.overlays.values() {
            let mut s = entry.state.borrow_mut();
            if s.active_rect.is_some() || s.dim_all {
                s.active_rect = None;
                s.dim_all = false;
                entry.window.set_visible(false);
                entry.drawing_area.queue_draw();
            }
        }
    }

    fn show_entry(&self, entry: &MonitorOverlay, active_rect: Option<Rect>, dim_all: bool) {
        self.set_tracking(true);
        {
            let mut s = entry.state.borrow_mut();
            s.active_rect = active_rect;
            s.dim_all = dim_all;
            s.window_radius = None;
        }
        entry.window.set_visible(self.picker_bounds.get().is_some());
        entry.drawing_area.queue_draw();
    }

    fn set_tracking(&self, enabled: bool) {
        if self.tracking.replace(enabled) != enabled {
            let _ = self.tracking_tx.send(enabled);
        }
    }

    pub fn refresh_picker_bounds(&self) {
        let Some(bounds) = self.bounds_rx.try_iter().last() else {
            return;
        };
        if !self.tracking.get() {
            return;
        }
        self.picker_bounds.set(Some(bounds));
        for entry in self.overlays.values() {
            let mut state = entry.state.borrow_mut();
            state.picker_rect = self.relative_rect(bounds, entry.geom);
            entry
                .window
                .set_visible(state.active_rect.is_some() || state.dim_all);
            entry.drawing_area.queue_draw();
        }
    }

    fn relative_rect(&self, global: Rect, geom: gdk::Rectangle) -> Option<Rect> {
        let mon_x = geom.x();
        let mon_y = geom.y();
        let mon_w = geom.width();
        let mon_h = geom.height();

        let left = global.x.max(mon_x);
        let top = global.y.max(mon_y);
        let right = (global.x + global.width).min(mon_x + mon_w);
        let bottom = (global.y + global.height).min(mon_y + mon_h);

        if right > left && bottom > top {
            Some(Rect {
                x: left - mon_x,
                y: top - mon_y,
                width: right - left,
                height: bottom - top,
            })
        } else {
            None
        }
    }
}
