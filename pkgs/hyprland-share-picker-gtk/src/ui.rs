use std::{
    cell::RefCell,
    collections::HashMap,
    fs,
    io::{Write, stdout},
    path::PathBuf,
    process::{self, Command},
    rc::Rc,
    sync::mpsc::{Receiver, channel},
    thread,
    time::{Duration, Instant},
};

use gtk4::{
    Application, ApplicationWindow, Box as GtkBox, Button, CenterBox, CheckButton, ContentFit,
    EventControllerKey, EventControllerMotion, FlowBox, GestureClick, GestureDrag, Image, Label,
    Orientation, Picture, PolicyType, PropagationPhase, ScrolledWindow, SelectionMode, Stack,
    StackTransitionType, ToggleButton, Widget, gdk, glib, prelude::*,
};
use gtk4_layer_shell::{Edge, KeyboardMode, Layer, LayerShell};

use crate::{
    capture::{CaptureManager, CaptureTarget, FrameMessage},
    config::{PickerConfig, load_config},
    css::install_css,
    desktop::{DesktopRegistry, create_app_icon, create_themed_icon},
    hyprland::{
        Client, Monitor, PortalWindowEntry, client_for_entry, parse_region, parse_region_details,
        parse_window_list, query_active_workspace, query_clients, query_monitors, window_at_point,
    },
    overlay::OverlayHighlighter,
};

pub fn picker_state_path() -> PathBuf {
    let state_home = std::env::var_os("XDG_STATE_HOME")
        .map(PathBuf::from)
        .unwrap_or_else(|| {
            let home = std::env::var_os("HOME")
                .map(PathBuf::from)
                .unwrap_or_default();
            home.join(".local").join("state")
        });
    state_home
        .join("hyprland-share-picker-gtk")
        .join("last-tab")
}

pub fn read_last_tab() -> String {
    if let Ok(content) = fs::read_to_string(picker_state_path()) {
        let t = content.trim();
        if t == "windows" || t == "screens" || t == "regions" {
            return t.to_string();
        }
    }
    "windows".to_string()
}

pub fn save_last_tab(tab: &str) {
    let path = picker_state_path();
    if let Some(parent) = path.parent() {
        let _ = fs::create_dir_all(parent);
    }
    let _ = fs::write(path, format!("{tab}\n"));
}

pub struct AppState {
    pub config: PickerConfig,
    pub allow_token: bool,
    pub selection: Option<String>,
    pub region_selection: Option<String>,
    pub active_tab: String,
    pub last_click_selection: Option<String>,
    pub last_click_time: Instant,
    pub hovered_id: Option<usize>,
    pub pick_receiver: Option<Receiver<Option<String>>>,
    pub capture_mgr: Rc<CaptureManager>,
    pub highlighter: Option<OverlayHighlighter>,
    pub clients: Vec<Client>,
    pub monitors: Vec<Monitor>,
    pub window_entries: Vec<PortalWindowEntry>,
    pub share_button: Option<Button>,
    pub pick_button_icon: Option<Image>,
    pub pick_button_label: Option<Label>,
    pub pick_button: Option<Button>,
    pub region_preview: Option<Picture>,
    pub region_heading: Option<Label>,
    pub region_description: Option<Label>,
    pub region_details_label: Option<Label>,
    pub region_draw_button: Option<Button>,
    pub card_buttons: Vec<(String, ToggleButton)>,
    pub card_targets: Vec<(usize, String, CaptureTarget)>,
    pub pictures: Rc<RefCell<HashMap<usize, Picture>>>,
    pub window: Option<ApplicationWindow>,
    pub stack: Option<Stack>,
}

pub fn build_ui(app: &Application, allow_token: bool, window_list_raw: Option<String>) {
    install_css();
    let config = load_config();
    let highlighter = OverlayHighlighter::new(&config);
    let desktop_reg = DesktopRegistry::new();

    let (frame_tx, frame_rx) = channel::<FrameMessage>();
    let capture_mgr = Rc::new(CaptureManager::new(frame_tx));
    let monitors = query_monitors();
    let clients = query_clients();
    let window_entries = if let Some(ref raw) = window_list_raw {
        parse_window_list(raw)
    } else {
        clients
            .iter()
            .map(|c| PortalWindowEntry {
                id: c.stable_id_string().unwrap_or_else(|| "0".into()),
                class: c.class.clone(),
                title: c.title.clone(),
                address: Some(c.address.clone()),
            })
            .collect()
    };

    let pictures: Rc<RefCell<HashMap<usize, Picture>>> = Rc::new(RefCell::new(HashMap::new()));
    let pictures_loop = pictures.clone();

    let initial_tab = read_last_tab();
    let state = Rc::new(RefCell::new(AppState {
        config: config.clone(),
        allow_token,
        selection: None,
        region_selection: None,
        active_tab: initial_tab.clone(),
        last_click_selection: None,
        last_click_time: Instant::now(),
        hovered_id: None,
        pick_receiver: None,
        capture_mgr: capture_mgr.clone(),
        highlighter,
        clients,
        monitors: monitors.clone(),
        window_entries,
        share_button: None,
        pick_button_icon: None,
        pick_button_label: None,
        pick_button: None,
        region_preview: None,
        region_heading: None,
        region_description: None,
        region_details_label: None,
        region_draw_button: None,
        card_buttons: Vec::new(),
        card_targets: Vec::new(),
        pictures,
        window: None,
        stack: None,
    }));

    // Attach frame delivery and slurp pick completion handler on GTK main loop (60 fps check)
    let state_loop = state.clone();
    glib::timeout_add_local(Duration::from_millis(16), move || {
        let pics = pictures_loop.borrow();
        while let Ok(msg) = frame_rx.try_recv() {
            if let Some(picture) = pics.get(&msg.card_id) {
                let texture = gdk::MemoryTexture::new(
                    msg.frame.width,
                    msg.frame.height,
                    gdk::MemoryFormat::R8g8b8a8,
                    &msg.frame.bytes,
                    msg.frame.stride,
                );
                picture.set_paintable(Some(&texture));
            }
        }

        let pick_result = {
            if let Ok(mut s) = state_loop.try_borrow_mut() {
                if let Some(ref rx) = s.pick_receiver {
                    match rx.try_recv() {
                        Ok(sel) => {
                            s.pick_receiver = None;
                            Some(sel)
                        }
                        Err(std::sync::mpsc::TryRecvError::Disconnected) => {
                            s.pick_receiver = None;
                            Some(None)
                        }
                        Err(std::sync::mpsc::TryRecvError::Empty) => None,
                    }
                } else {
                    None
                }
            } else {
                None
            }
        };

        if let Some(selection) = pick_result {
            finish_pick(state_loop.clone(), selection);
        }

        glib::ControlFlow::Continue
    });

    let window = ApplicationWindow::builder()
        .application(app)
        .title("Share your screen")
        .build();
    window.set_size_request(640, 460);
    window.add_css_class("share-picker");

    let mut init_x = 0;
    let mut init_y = 0;

    if gtk4_layer_shell::is_supported() {
        window.init_layer_shell();
        window.set_layer(Layer::Overlay);
        window.set_keyboard_mode(KeyboardMode::OnDemand);
        window.set_exclusive_zone(-1);
        window.set_namespace("hyprland-share-picker");

        let display = gdk::Display::default();
        let focused_name = monitors.iter().find(|m| m.focused).map(|m| m.name.as_str());
        let mut target_gdk_mon = None;

        if let Some(ref disp) = display {
            let gdk_monitors = disp.monitors();
            for i in 0..gdk_monitors.n_items() {
                if let Some(mon) = gdk_monitors.item(i).and_downcast::<gdk::Monitor>() {
                    if let Some(ref name) = mon.connector() {
                        if focused_name == Some(name.as_str()) {
                            target_gdk_mon = Some(mon);
                            break;
                        }
                    }
                }
            }
            if target_gdk_mon.is_none() && gdk_monitors.n_items() > 0 {
                target_gdk_mon = gdk_monitors.item(0).and_downcast::<gdk::Monitor>();
            }
        }

        let (mon_w, mon_h) = if let Some(ref mon) = target_gdk_mon {
            window.set_monitor(mon);
            let geom = mon.geometry();
            (geom.width(), geom.height())
        } else {
            (1920, 1080)
        };

        let win_w = 1180.min(mon_w - 60).max(640);
        let win_h = 800.min(mon_h - 60).max(460);
        init_x = ((mon_w - win_w) / 2).max(0);
        init_y = ((mon_h - win_h) / 2).max(0);

        window.set_default_size(win_w, win_h);
        window.set_anchor(Edge::Top, true);
        window.set_anchor(Edge::Left, true);
        window.set_margin(Edge::Left, init_x);
        window.set_margin(Edge::Top, init_y);
    } else {
        window.set_default_size(1180, 800);
    }

    // Key handling: Esc to quit, Enter to share
    let key_controller = EventControllerKey::new();
    let state_key = state.clone();
    key_controller.connect_key_pressed(move |_ctrl, keyval, _keycode, _mod| {
        if keyval == gdk::Key::Escape {
            if let Some(ref h) = state_key.borrow().highlighter {
                h.clear();
            }
            process::exit(1);
        }
        if keyval == gdk::Key::Return || keyval == gdk::Key::KP_Enter {
            let s = state_key.borrow();
            if let Some(ref sel) = s.selection {
                emit_selection(sel, s.allow_token);
            }
            return glib::Propagation::Stop;
        }
        glib::Propagation::Proceed
    });
    window.add_controller(key_controller);

    let content = GtkBox::new(Orientation::Vertical, 0);
    content.add_css_class("picker-content");

    // Header
    let header = GtkBox::new(Orientation::Vertical, 4);
    header.add_css_class("picker-header");
    header.set_margin_top(24);
    header.set_margin_bottom(18);
    header.set_margin_start(28);
    header.set_margin_end(28);

    if gtk4_layer_shell::is_supported() {
        header.set_cursor_from_name(Some("grab"));

        let drag = GestureDrag::new();
        let start_pos = Rc::new(RefCell::new((0i32, 0i32)));
        let start_pos_begin = start_pos.clone();
        let win_begin = window.clone();
        let header_begin = header.clone();
        drag.connect_drag_begin(move |_g, _x, _y| {
            header_begin.set_cursor_from_name(Some("grabbing"));
            let cur_x = win_begin.margin(Edge::Left);
            let cur_y = win_begin.margin(Edge::Top);
            *start_pos_begin.borrow_mut() = (cur_x, cur_y);
        });

        let win_drag = window.clone();
        let start_pos_update = start_pos.clone();
        drag.connect_drag_update(move |_g, offset_x, offset_y| {
            let (sx, sy) = *start_pos_update.borrow();
            win_drag.set_margin(Edge::Left, sx + offset_x as i32);
            win_drag.set_margin(Edge::Top, sy + offset_y as i32);
        });

        let header_end = header.clone();
        drag.connect_drag_end(move |_g, _offset_x, _offset_y| {
            header_end.set_cursor_from_name(Some("grab"));
        });

        header.add_controller(drag);

        let double_click = GestureClick::new();
        double_click.set_button(1);
        let win_reset = window.clone();
        double_click.connect_pressed(move |_g, n_press, _x, _y| {
            if n_press == 2 {
                win_reset.set_margin(Edge::Left, init_x);
                win_reset.set_margin(Edge::Top, init_y);
            }
        });
        header.add_controller(double_click);
    }

    let title_label = Label::new(Some("Choose what to share"));
    title_label.set_xalign(0.0);
    title_label.add_css_class("title-1");

    let subtitle_label = Label::new(Some(
        "Select an entire screen, a window, or a specific region. Previews update automatically.",
    ));
    subtitle_label.set_xalign(0.0);
    subtitle_label.set_wrap(true);
    subtitle_label.add_css_class("dim-label");

    header.append(&title_label);
    header.append(&subtitle_label);
    content.append(&header);

    // Stack
    let stack = Stack::new();
    stack.set_transition_type(StackTransitionType::Crossfade);
    stack.set_vexpand(true);

    let mut next_card_id = 0;
    let window_page = make_window_page(state.clone(), &desktop_reg, &mut next_card_id);
    let screen_page = make_screen_page(state.clone(), &mut next_card_id);
    let region_page = make_region_page(state.clone(), &mut next_card_id);

    stack.add_titled(&window_page, Some("windows"), "Window");
    stack.add_titled(&screen_page, Some("screens"), "Screen");
    stack.add_titled(&region_page, Some("regions"), "Region");
    stack.set_visible_child_name(&initial_tab);

    // Nav Bar
    let nav_bar = CenterBox::new();
    nav_bar.set_margin_bottom(12);
    nav_bar.set_margin_start(28);
    nav_bar.set_margin_end(28);

    let switcher = make_tab_switcher(&stack);
    let pick_btn = make_pick_button(state.clone());

    nav_bar.set_center_widget(Some(&switcher));
    nav_bar.set_end_widget(Some(&pick_btn));
    content.append(&nav_bar);
    content.append(&stack);

    // Footer
    let footer = GtkBox::new(Orientation::Horizontal, 12);
    footer.set_margin_top(16);
    footer.set_margin_bottom(20);
    footer.set_margin_start(28);
    footer.set_margin_end(28);

    let token_check = CheckButton::with_label("Remember this choice");
    token_check.set_active(allow_token);
    token_check.set_tooltip_text(Some(
        "Allow this application to reuse the chosen source later",
    ));
    let state_tok = state.clone();
    token_check.connect_toggled(move |btn| {
        state_tok.borrow_mut().allow_token = btn.is_active();
    });
    footer.append(&token_check);

    let spacer = GtkBox::new(Orientation::Horizontal, 0);
    spacer.set_hexpand(true);
    footer.append(&spacer);

    let cancel_btn = Button::with_label("Cancel");
    let state_cancel = state.clone();
    cancel_btn.connect_clicked(move |_| {
        if let Some(ref h) = state_cancel.borrow().highlighter {
            h.clear();
        }
        process::exit(1);
    });
    footer.append(&cancel_btn);

    let share_btn = Button::with_label("Share");
    share_btn.add_css_class("suggested-action");
    share_btn.set_sensitive(false);
    let state_share = state.clone();
    share_btn.connect_clicked(move |_| {
        let s = state_share.borrow();
        if let Some(ref sel) = s.selection {
            emit_selection(sel, s.allow_token);
        }
    });
    footer.append(&share_btn);
    content.append(&footer);

    window.set_child(Some(&content));

    // Handle close request
    let state_close = state.clone();
    window.connect_close_request(move |_| {
        if let Some(ref h) = state_close.borrow().highlighter {
            h.clear();
        }
        process::exit(1);
    });

    {
        let mut s = state.borrow_mut();
        s.share_button = Some(share_btn);
        s.window = Some(window.clone());
        s.stack = Some(stack.clone());
    }

    let state_tab_change = state.clone();
    stack.connect_visible_child_name_notify(move |stk| {
        if let Some(name) = stk.visible_child_name() {
            let mut s = state_tab_change.borrow_mut();
            s.active_tab = name.to_string();
            save_last_tab(&name);
            s.capture_mgr.set_active_tab(&name);
            update_pick_button_ui(&mut s);
            update_overlay_highlight(&s);
        }
    });

    capture_mgr.set_active_tab(&initial_tab);
    window.present();
}

fn make_tab_switcher(stack: &Stack) -> GtkBox {
    let box_switcher = GtkBox::new(Orientation::Horizontal, 4);
    let mut group_lead: Option<ToggleButton> = None;

    let tabs = [
        ("windows", "Window", "view-grid-symbolic"),
        ("screens", "Screen", "video-display-symbolic"),
        ("regions", "Region", "selection-rectangular-symbolic"),
    ];

    let current = stack
        .visible_child_name()
        .unwrap_or_else(|| "windows".into());

    for (name, label, icon) in tabs {
        let btn = ToggleButton::new();
        if let Some(ref lead) = group_lead {
            btn.set_group(Some(lead));
        } else {
            group_lead = Some(btn.clone());
        }

        btn.set_active(current == name);

        let cbox = GtkBox::new(Orientation::Horizontal, 6);
        cbox.set_margin_top(5);
        cbox.set_margin_bottom(5);
        cbox.set_margin_start(10);
        cbox.set_margin_end(10);

        let img = Image::from_icon_name(icon);
        img.set_pixel_size(16);
        let lbl = Label::new(Some(label));

        cbox.append(&img);
        cbox.append(&lbl);
        btn.set_child(Some(&cbox));

        let stack_clone = stack.clone();
        let name_str = name.to_string();
        btn.connect_toggled(move |b| {
            if b.is_active() {
                stack_clone.set_visible_child_name(&name_str);
            }
        });

        box_switcher.append(&btn);
    }

    box_switcher
}

fn make_pick_button(state: Rc<RefCell<AppState>>) -> Button {
    let btn = Button::new();
    btn.add_css_class("flat");

    let cbox = GtkBox::new(Orientation::Horizontal, 6);
    cbox.set_margin_top(5);
    cbox.set_margin_bottom(5);
    cbox.set_margin_start(10);
    cbox.set_margin_end(10);

    let icon = Image::from_icon_name("edit-select-symbolic");
    icon.set_pixel_size(16);
    let label = Label::new(Some("Pick"));

    cbox.append(&icon);
    cbox.append(&label);
    btn.set_child(Some(&cbox));

    {
        let mut s = state.borrow_mut();
        s.pick_button_icon = Some(icon);
        s.pick_button_label = Some(label);
        s.pick_button = Some(btn.clone());
        update_pick_button_ui(&mut s);
    }

    let state_click = state.clone();
    btn.connect_clicked(move |_| {
        let tab = state_click.borrow().active_tab.clone();
        match tab.as_str() {
            "windows" => trigger_pick_window(state_click.clone()),
            "screens" => trigger_pick_screen(state_click.clone()),
            "regions" => trigger_pick_region(state_click.clone()),
            _ => {}
        }
    });

    btn
}

fn update_pick_button_ui(state: &mut AppState) {
    let (icon, label, tooltip) = match state.active_tab.as_str() {
        "windows" => ("edit-select-symbolic", "Pick", "Click any window on screen"),
        "screens" => (
            "video-display-symbolic",
            "Pick",
            "Click any screen directly",
        ),
        "regions" => {
            if state.region_selection.is_some() {
                (
                    "document-edit-symbolic",
                    "Edit region…",
                    "Redraw the selected screen region",
                )
            } else {
                (
                    "edit-select-symbolic",
                    "Pick",
                    "Draw a rectangle directly on screen",
                )
            }
        }
        _ => ("edit-select-symbolic", "Pick", "Pick directly"),
    };

    if let Some(ref icon_widget) = state.pick_button_icon {
        icon_widget.set_icon_name(Some(icon));
    }
    if let Some(ref label_widget) = state.pick_button_label {
        label_widget.set_label(label);
    }
    if let Some(ref btn) = state.pick_button {
        btn.set_tooltip_text(Some(tooltip));
    }
}

fn make_window_page(
    state: Rc<RefCell<AppState>>,
    desktop_reg: &DesktopRegistry,
    next_id: &mut usize,
) -> ScrolledWindow {
    let flow = FlowBox::new();
    flow.set_selection_mode(SelectionMode::None);
    let cols = state.borrow().config.columns;
    flow.set_max_children_per_line(cols as u32);
    flow.set_min_children_per_line(cols as u32);
    flow.set_homogeneous(true);
    flow.set_column_spacing(14);
    flow.set_row_spacing(14);
    flow.set_margin_top(4);
    flow.set_margin_bottom(16);
    flow.set_margin_start(28);
    flow.set_margin_end(28);

    let (entries, clients) = {
        let s = state.borrow();
        (s.window_entries.clone(), s.clients.clone())
    };

    let active_ws = query_active_workspace().map(|w| w.id);

    let mut sorted_entries: Vec<(PortalWindowEntry, Option<Client>)> = entries
        .into_iter()
        .map(|e| {
            let cl = client_for_entry(&e, &clients).cloned();
            (e, cl)
        })
        .collect();

    sorted_entries.sort_by(|(ea, ca), (eb, cb)| {
        let ws_a = ca.as_ref().map(|c| c.workspace.id);
        let ws_b = cb.as_ref().map(|c| c.workspace.id);

        let active_a = ws_a == active_ws;
        let active_b = ws_b == active_ws;

        if active_a != active_b {
            return active_b.cmp(&active_a);
        }
        if ws_a != ws_b {
            return ws_a.cmp(&ws_b);
        }
        ea.title.to_lowercase().cmp(&eb.title.to_lowercase())
    });

    let mut group_lead: Option<ToggleButton> = None;

    for (entry, client) in sorted_entries {
        let card_id = *next_id;
        *next_id += 1;

        let selection = format!("window:{}", entry.id);
        let title = if let Some(ref c) = client {
            if !c.title.is_empty() {
                c.title.clone()
            } else {
                entry.title.clone()
            }
        } else {
            entry.title.clone()
        };

        let subtitle = if let Some(ref c) = client {
            format!("{} · Workspace {}", c.class, c.workspace.name)
        } else {
            format!("{} · Window", entry.class)
        };

        let target = if let Some(ref c) = client {
            if let Some(stable) = c.stable_id_string() {
                CaptureTarget::Window(stable)
            } else {
                CaptureTarget::Window(entry.id.clone())
            }
        } else {
            CaptureTarget::Window(entry.id.clone())
        };

        let icon_widget = if let Some(ref c) = client {
            create_app_icon(desktop_reg, &c.class, &c.initial_class, 32)
        } else {
            create_app_icon(desktop_reg, &entry.class, "", 32)
        };

        let card = make_source_card(
            state.clone(),
            card_id,
            &selection,
            &title,
            &subtitle,
            Some(icon_widget),
            target,
            "windows",
            &mut group_lead,
        );
        flow.insert(&card, -1);
    }

    let scroll = ScrolledWindow::new();
    scroll.set_policy(PolicyType::Never, PolicyType::Automatic);
    scroll.set_child(Some(&flow));
    scroll
}

fn make_screen_page(state: Rc<RefCell<AppState>>, next_id: &mut usize) -> ScrolledWindow {
    let flow = FlowBox::new();
    flow.set_selection_mode(SelectionMode::None);
    let cols = state.borrow().config.columns;
    flow.set_max_children_per_line(cols as u32);
    flow.set_min_children_per_line(cols as u32);
    flow.set_homogeneous(true);
    flow.set_column_spacing(14);
    flow.set_row_spacing(14);
    flow.set_margin_top(4);
    flow.set_margin_bottom(16);
    flow.set_margin_start(28);
    flow.set_margin_end(28);

    let monitors = state.borrow().monitors.clone();
    let mut group_lead: Option<ToggleButton> = None;

    for mon in monitors {
        let card_id = *next_id;
        *next_id += 1;

        let selection = format!("screen:{}", mon.name);
        let title = mon.name.clone();
        let subtitle = format!(
            "{} · {} × {} px",
            if !mon.description.is_empty() {
                mon.description.clone()
            } else {
                "Screen".into()
            },
            mon.width,
            mon.height
        );
        let target = CaptureTarget::Output(mon.name.clone());

        let icon_widget = create_themed_icon("video-display-symbolic", 32);

        let card = make_source_card(
            state.clone(),
            card_id,
            &selection,
            &title,
            &subtitle,
            Some(icon_widget),
            target,
            "screens",
            &mut group_lead,
        );
        flow.insert(&card, -1);
    }

    let scroll = ScrolledWindow::new();
    scroll.set_policy(PolicyType::Never, PolicyType::Automatic);
    scroll.set_child(Some(&flow));
    scroll
}

fn make_region_page(state: Rc<RefCell<AppState>>, next_id: &mut usize) -> GtkBox {
    let box_main = GtkBox::new(Orientation::Vertical, 14);
    box_main.set_halign(gtk4::Align::Center);
    box_main.set_valign(gtk4::Align::Center);
    box_main.set_vexpand(true);
    box_main.set_hexpand(true);
    box_main.set_margin_top(40);
    box_main.set_margin_bottom(40);

    let icon = Image::from_icon_name("selection-rectangular-symbolic");
    icon.set_pixel_size(48);
    box_main.append(&icon);

    let heading = Label::new(Some("Select a region"));
    heading.add_css_class("title-2");
    box_main.append(&heading);

    let desc = Label::new(Some(
        "Click and drag on any screen to select a specific rectangular area to share.",
    ));
    desc.set_wrap(true);
    desc.add_css_class("dim-label");
    box_main.append(&desc);

    let preview = Picture::new();
    preview.add_css_class("region-preview");
    preview.set_can_shrink(true);
    preview.set_size_request(420, 236);
    preview.set_content_fit(ContentFit::Contain);
    preview.set_visible(false);
    box_main.append(&preview);

    let details = Label::new(None);
    details.add_css_class("dim-label");
    details.set_visible(false);
    box_main.append(&details);

    let draw_btn = Button::with_label("Draw region…");
    draw_btn.add_css_class("suggested-action");
    draw_btn.set_margin_top(8);
    let state_draw = state.clone();
    draw_btn.connect_clicked(move |_| {
        trigger_pick_region(state_draw.clone());
    });
    box_main.append(&draw_btn);

    // Register region preview stream
    let card_id = *next_id;
    *next_id += 1;

    state
        .borrow()
        .pictures
        .borrow_mut()
        .insert(card_id, preview.clone());

    let default_target = CaptureTarget::Region {
        output: String::new(),
        x: 0,
        y: 0,
        width: 1,
        height: 1,
    };

    let scale = state.borrow().config.scale;
    let fps = state.borrow().config.refresh_rate;
    state
        .borrow()
        .capture_mgr
        .register_card(card_id, default_target, fps, scale, "regions");

    {
        let mut s = state.borrow_mut();
        s.region_preview = Some(preview);
        s.region_heading = Some(heading);
        s.region_description = Some(desc);
        s.region_details_label = Some(details);
        s.region_draw_button = Some(draw_btn);
        s.card_targets.push((
            card_id,
            "region".to_string(),
            CaptureTarget::Output("".into()),
        ));
    }

    box_main
}

fn make_source_card(
    state: Rc<RefCell<AppState>>,
    card_id: usize,
    selection: &str,
    title: &str,
    subtitle: &str,
    icon: Option<Widget>,
    target: CaptureTarget,
    tab: &str,
    group_lead: &mut Option<ToggleButton>,
) -> ToggleButton {
    let card = ToggleButton::new();
    card.add_css_class("source-card");
    card.set_hexpand(true);
    card.set_size_request(240, -1);

    if let Some(lead) = group_lead {
        card.set_group(Some(lead));
    } else {
        *group_lead = Some(card.clone());
    }

    let body = GtkBox::new(Orientation::Vertical, 10);
    let preview = Picture::new();
    preview.add_css_class("preview");
    preview.set_can_shrink(true);
    preview.set_size_request(-1, 180);
    preview.set_content_fit(ContentFit::Cover);
    preview.set_halign(gtk4::Align::Fill);
    body.append(&preview);

    let info_box = GtkBox::new(Orientation::Horizontal, 12);
    info_box.set_margin_bottom(12);
    info_box.set_margin_start(14);
    info_box.set_margin_end(14);
    info_box.set_valign(gtk4::Align::Center);

    if let Some(ref icon_w) = icon {
        info_box.append(icon_w);
    }

    let labels = GtkBox::new(Orientation::Vertical, 2);
    labels.set_hexpand(true);

    let name_label = Label::new(Some(title));
    name_label.set_xalign(0.0);
    name_label.set_ellipsize(gtk4::pango::EllipsizeMode::End);
    name_label.add_css_class("heading");

    let detail_label = Label::new(Some(subtitle));
    detail_label.set_xalign(0.0);
    detail_label.set_ellipsize(gtk4::pango::EllipsizeMode::End);
    detail_label.add_css_class("dim-label");

    labels.append(&name_label);
    labels.append(&detail_label);
    info_box.append(&labels);
    body.append(&info_box);
    card.set_child(Some(&body));

    state
        .borrow()
        .pictures
        .borrow_mut()
        .insert(card_id, preview.clone());

    let scale = state.borrow().config.scale;
    state.borrow().capture_mgr.register_card(
        card_id,
        target.clone(),
        1.0, // initial idle fps
        scale,
        tab,
    );

    let sel_str = selection.to_string();
    {
        let mut s = state.borrow_mut();
        s.card_buttons.push((sel_str.clone(), card.clone()));
        s.card_targets.push((card_id, sel_str.clone(), target));
    }

    // Toggle event
    let state_toggle = state.clone();
    let sel_toggle = sel_str.clone();
    card.connect_toggled(move |c| {
        if c.is_active() {
            {
                let mut s = match state_toggle.try_borrow_mut() {
                    Ok(s) => s,
                    Err(_) => return,
                };
                s.selection = Some(sel_toggle.clone());
                if let Some(ref btn) = s.share_button {
                    btn.set_sensitive(true);
                }
            }
            if let Ok(s) = state_toggle.try_borrow() {
                update_card_fps(&s);
                update_overlay_highlight(&s);
            }
        }
    });

    // Double click
    let click = GestureClick::new();
    click.set_button(1);
    click.set_propagation_phase(PropagationPhase::Capture);
    let state_click = state.clone();
    let sel_click = sel_str.clone();
    click.connect_pressed(move |_g, presses, _x, _y| {
        let now = Instant::now();
        let (is_double, allow_token) = {
            let mut s = match state_click.try_borrow_mut() {
                Ok(s) => s,
                Err(_) => return,
            };
            let is_double = presses == 2
                || (s.last_click_selection.as_ref() == Some(&sel_click)
                    && now.duration_since(s.last_click_time) < Duration::from_millis(500));

            s.last_click_selection = Some(sel_click.clone());
            s.last_click_time = now;
            (is_double, s.allow_token)
        };

        if is_double {
            emit_selection(&sel_click, allow_token);
        }
    });
    card.add_controller(click);

    // Hover Enter & Leave
    let motion = EventControllerMotion::new();
    motion.set_propagation_phase(PropagationPhase::Capture);

    let state_enter = state.clone();
    motion.connect_enter(move |_m, _x, _y| {
        {
            let mut s = match state_enter.try_borrow_mut() {
                Ok(s) => s,
                Err(_) => return,
            };
            s.hovered_id = Some(card_id);
        }
        if let Ok(s) = state_enter.try_borrow() {
            update_card_fps(&s);
            update_overlay_highlight(&s);
        }
    });

    let state_leave = state.clone();
    motion.connect_leave(move |_m| {
        {
            let mut s = match state_leave.try_borrow_mut() {
                Ok(s) => s,
                Err(_) => return,
            };
            if s.hovered_id == Some(card_id) {
                s.hovered_id = None;
            } else {
                return;
            }
        }
        if let Ok(s) = state_leave.try_borrow() {
            update_card_fps(&s);
            update_overlay_highlight(&s);
        }
    });

    card.add_controller(motion);
    card
}

fn update_card_fps(state: &AppState) {
    let focused_id = if let Some(hid) = state.hovered_id {
        Some(hid)
    } else if let Some(ref sel) = state.selection {
        state
            .card_targets
            .iter()
            .find(|(_, s, _)| s == sel)
            .map(|(id, _, _)| *id)
    } else {
        None
    };

    let high_fps = state.config.refresh_rate;
    for (id, _, _) in &state.card_targets {
        let fps = if Some(*id) == focused_id {
            high_fps
        } else {
            1.0
        };
        state.capture_mgr.set_card_fps(*id, fps);
    }
}

fn update_overlay_highlight(state: &AppState) {
    let highlighter = match state.highlighter.as_ref() {
        Some(h) => h,
        None => return,
    };

    let target_sel = if let Some(hid) = state.hovered_id {
        state
            .card_targets
            .iter()
            .find(|(id, _, _)| *id == hid)
            .map(|(_, s, _)| s.clone())
    } else {
        state.selection.clone()
    };

    let sel = match target_sel {
        Some(s) => s,
        None => {
            highlighter.clear();
            return;
        }
    };

    let monitors = query_monitors();
    let monitors_to_use = if !monitors.is_empty() {
        monitors
    } else {
        state.monitors.clone()
    };

    if let Some(name) = sel.strip_prefix("screen:") {
        highlighter.highlight_screen(name);
    } else if let Some(id) = sel.strip_prefix("window:") {
        let clients = query_clients();
        if let Some(c) = clients
            .iter()
            .find(|cl| cl.stable_id_string().as_deref() == Some(id))
        {
            highlighter.highlight_window(c, &monitors_to_use);
        } else {
            highlighter.clear();
        }
    } else if sel.starts_with("region:") {
        if let Some(details) = parse_region_details(&sel, &monitors_to_use) {
            highlighter.highlight_region(&details);
        } else {
            highlighter.clear();
        }
    } else {
        highlighter.clear();
    }
}

fn trigger_pick_screen(state: Rc<RefCell<AppState>>) {
    if let Some(ref h) = state.borrow().highlighter {
        h.clear();
    }
    if let Some(ref win) = state.borrow().window {
        win.set_visible(false);
    }

    let (tx, rx) = channel::<Option<String>>();
    thread::spawn(move || {
        let res = Command::new("slurp").args(["-o", "-f", "%o"]).output();

        let selection = if let Ok(out) = res {
            if out.status.success() {
                let s = String::from_utf8_lossy(&out.stdout).trim().to_string();
                if !s.is_empty() {
                    Some(format!("screen:{s}"))
                } else {
                    None
                }
            } else {
                None
            }
        } else {
            None
        };

        let _ = tx.send(selection);
    });

    state.borrow_mut().pick_receiver = Some(rx);
}

fn trigger_pick_window(state: Rc<RefCell<AppState>>) {
    if let Some(ref h) = state.borrow().highlighter {
        h.clear();
    }
    if let Some(ref win) = state.borrow().window {
        win.set_visible(false);
    }

    let (tx, rx) = channel::<Option<String>>();
    thread::spawn(move || {
        let res = Command::new("slurp").args(["-p", "-f", "%x %y"]).output();

        let coords = if let Ok(out) = res {
            if out.status.success() {
                let s = String::from_utf8_lossy(&out.stdout).trim().to_string();
                let parts: Vec<&str> = s.split_whitespace().collect();
                if parts.len() == 2 {
                    if let (Ok(x), Ok(y)) = (parts[0].parse::<i32>(), parts[1].parse::<i32>()) {
                        Some((x, y))
                    } else {
                        None
                    }
                } else {
                    None
                }
            } else {
                None
            }
        } else {
            None
        };

        let selection = coords.and_then(|(x, y)| {
            let clients = query_clients();
            window_at_point(x, y, &clients)
                .and_then(|c| c.stable_id_string().map(|id| format!("window:{id}")))
        });

        let _ = tx.send(selection);
    });

    state.borrow_mut().pick_receiver = Some(rx);
}

fn trigger_pick_region(state: Rc<RefCell<AppState>>) {
    if let Some(ref h) = state.borrow().highlighter {
        h.clear();
    }
    if let Some(ref win) = state.borrow().window {
        win.set_visible(false);
    }

    let monitors = state.borrow().monitors.clone();
    let (tx, rx) = channel::<Option<String>>();
    thread::spawn(move || {
        let res = Command::new("slurp")
            .args(["-f", "%o %x %y %w %h"])
            .output();

        let selection = if let Ok(out) = res {
            if out.status.success() {
                let s = String::from_utf8_lossy(&out.stdout);
                parse_region(&s, &monitors)
            } else {
                None
            }
        } else {
            None
        };

        let _ = tx.send(selection);
    });

    state.borrow_mut().pick_receiver = Some(rx);
}

fn finish_pick(state: Rc<RefCell<AppState>>, selection: Option<String>) {
    if let Some(ref win) = state.borrow().window {
        win.set_visible(true);
        win.present();
    }

    if let Some(sel) = selection {
        if sel.starts_with("region:") {
            set_region_selection(state.clone(), &sel);
            update_overlay_highlight(&state.borrow());
        } else {
            let allow_token = state.borrow().allow_token;
            emit_selection(&sel, allow_token);
        }
    } else {
        update_overlay_highlight(&state.borrow());
    }
}

fn set_region_selection(state: Rc<RefCell<AppState>>, sel: &str) {
    let mut s = state.borrow_mut();
    let details = match parse_region_details(sel, &s.monitors) {
        Some(d) => d,
        None => return,
    };

    s.region_selection = Some(sel.to_string());
    s.selection = Some(sel.to_string());
    if let Some(ref btn) = s.share_button {
        btn.set_sensitive(true);
    }
    if let Some(ref heading) = s.region_heading {
        heading.set_label("Region ready to share");
    }
    if let Some(ref desc) = s.region_description {
        desc.set_label(
            "Review the live preview below. Choose Edit region to redraw it, then click Share when ready.",
        );
    }
    if let Some(ref prev) = s.region_preview {
        prev.set_visible(true);
    }
    if let Some(ref dt) = s.region_details_label {
        dt.set_label(&format!(
            "{} · {} × {} px",
            details.output, details.width, details.height
        ));
        dt.set_visible(true);
    }
    if let Some(ref draw_btn) = s.region_draw_button {
        draw_btn.set_label("Edit region…");
    }

    update_pick_button_ui(&mut s);

    let target = CaptureTarget::Region {
        output: details.output.clone(),
        x: details.x,
        y: details.y,
        width: details.width,
        height: details.height,
    };

    for (id, name, _) in &s.card_targets {
        if name == "region" {
            s.capture_mgr.update_region(*id, target.clone());
            break;
        }
    }
}

pub fn emit_selection(selection: &str, allow_token: bool) {
    let prefix = if allow_token { "r" } else { "" };
    let record = format!("[SELECTION]{prefix}/{selection}\n");
    let mut out = stdout().lock();
    let _ = out.write_all(record.as_bytes());
    let _ = out.flush();
    process::exit(0);
}
