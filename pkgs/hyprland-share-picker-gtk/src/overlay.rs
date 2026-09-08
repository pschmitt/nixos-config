use std::{cell::RefCell, collections::HashMap, rc::Rc};

use gtk4::{DrawingArea, Window, cairo, gdk, prelude::*};
use gtk4_layer_shell::{Edge, KeyboardMode, Layer, LayerShell};

use crate::{
    config::{DEFAULT_HIGHLIGHT_RGBA, PickerConfig, parse_rgba_color},
    hyprland::{Client, Monitor, RegionDetails},
};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Rect {
    pub x: i32,
    pub y: i32,
    pub width: i32,
    pub height: i32,
}

struct MonitorOverlay {
    window: Window,
    drawing_area: DrawingArea,
    geom: gdk::Rectangle,
    state: Rc<RefCell<OverlayState>>,
}

struct OverlayState {
    active_rect: Option<Rect>,
    dim_all: bool,
}

pub struct OverlayHighlighter {
    overlays: HashMap<String, MonitorOverlay>,
    config: PickerConfig,
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
        let display = gdk::Display::default()?;
        let (r, g, b, _) = parse_rgba_color(&config.highlight_color, DEFAULT_HIGHLIGHT_RGBA);
        let (dim_r, dim_g, dim_b, _) = parse_rgba_color(&config.dim_color, (0.0, 0.0, 0.0, 1.0));

        let mut highlighter = Self {
            overlays: HashMap::new(),
            config: config.clone(),
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
            dim_all: false,
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
                    cr.rectangle(
                        target_rect.x as f64,
                        target_rect.y as f64,
                        target_rect.width as f64,
                        target_rect.height as f64,
                    );
                    cr.set_fill_rule(cairo::FillRule::EvenOdd);
                }
                cr.set_source_rgba(dim_r, dim_g, dim_b, dim_alpha);
                let _ = cr.fill();
                let _ = cr.restore();
            }

            if let Some(target_rect) = rect {
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

    pub fn highlight_window(&self, client: &Client, monitors: &[Monitor]) {
        if client.at.len() != 2 || client.size.len() != 2 {
            self.clear();
            return;
        }

        if !client.is_visible_on_any_monitor(monitors) {
            self.clear();
            return;
        }

        let global_rect = Rect {
            x: client.at[0],
            y: client.at[1],
            width: client.size[0],
            height: client.size[1],
        };

        for (connector, entry) in &self.overlays {
            let is_mon_showing = monitors
                .iter()
                .find(|m| &m.name == connector)
                .map_or(false, |m| client.is_visible_on_monitor(m));

            if is_mon_showing {
                let target_on_mon = self.relative_rect(global_rect, entry.geom);
                if target_on_mon.is_some() {
                    self.show_entry(entry, target_on_mon, false);
                } else {
                    self.show_entry(entry, None, true);
                }
            } else {
                self.show_entry(entry, None, true);
            }
        }
    }

    pub fn clear(&self) {
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
        {
            let mut s = entry.state.borrow_mut();
            s.active_rect = active_rect;
            s.dim_all = dim_all;
        }
        entry.window.set_visible(true);
        entry.drawing_area.queue_draw();
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
