use std::{
    cell::RefCell,
    collections::HashMap,
    fs,
    io::{Write, stdout},
    os::fd::AsRawFd,
    path::PathBuf,
    process::{self, Command},
    rc::Rc,
    sync::{
        Arc,
        atomic::{AtomicBool, Ordering},
        mpsc::{Receiver, Sender, channel, sync_channel},
    },
    thread,
    time::{Duration, Instant},
};

use gtk4::{
    Application, ApplicationWindow, Box as GtkBox, Button, CenterBox, CheckButton, ContentFit,
    EventControllerKey, EventControllerMotion, FlowBox, GestureClick, GestureDrag, Image, Label,
    Orientation, Picture, PolicyType, PropagationPhase, ScrolledWindow, SelectionMode, Stack,
    StackTransitionType, ToggleButton, Widget, gdk, glib, prelude::*,
};

use crate::{
    capture::{
        CaptureCommand, CaptureManager, CaptureTarget, DmabufFrame, FrameMessage, FramePayload,
    },
    config::{PickerConfig, load_config},
    css::install_css,
    decoration,
    desktop::{DesktopRegistry, create_app_icon, create_themed_icon},
    hyprland::{
        Client, Monitor, PortalWindowEntry, client_for_entry, parse_region, parse_region_details,
        parse_window_list, query_active_workspace, query_clients, query_cursor_pos, query_monitors,
        spawn_state_watcher, window_at_point, window_to_region,
    },
    indicator,
    overlay::OverlayHighlighter,
};

/// How long the mark stays after the pointer leaves a card without
/// entering another.
const HOVER_LEAVE_DELAY: Duration = Duration::from_millis(150);

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

#[derive(Clone)]
pub struct WindowCardItem {
    pub card_id: usize,
    pub address: String,
    pub portal_id: String,
    pub selection: String,
    pub is_portal_authorized: bool,
    pub title: String,
    pub class: String,
    pub workspace_id: i64,
    pub workspace_name: String,
    pub button: ToggleButton,
    pub name_label: Label,
    pub detail_label: Label,
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
    /// Window under the cursor during the direct window pick.
    pub pick_hover_rx: Option<Receiver<Option<Client>>>,
    pub capture_mgr: Rc<CaptureManager>,
    pub highlighter: Option<OverlayHighlighter>,
    pub clients: Vec<Client>,
    pub monitors: Vec<Monitor>,
    pub window_entries: Vec<PortalWindowEntry>,
    pub has_window_list_raw: bool,
    pub next_card_id: usize,
    pub desktop_reg: Rc<DesktopRegistry>,
    pub selected_window_preview: Option<Picture>,
    pub selected_window_heading: Option<Label>,
    pub selected_window_id: Option<usize>,
    pub window_flow: Option<FlowBox>,
    pub window_group_lead: Option<ToggleButton>,
    pub window_cards: HashMap<String, WindowCardItem>,
    pub last_active_ws: Option<i64>,
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
    pub card_widgets: HashMap<usize, ToggleButton>,
    pub pictures: Rc<RefCell<HashMap<usize, Picture>>>,
    pub window: Option<ApplicationWindow>,
    pub stack: Option<Stack>,
}

pub fn build_ui(app: &Application, allow_token: bool, window_list_raw: Option<String>) {
    install_css();
    let config = load_config();
    let highlighter = OverlayHighlighter::new(&config);
    let desktop_reg = Rc::new(DesktopRegistry::new());

    // Frame delivery stops when the native window is unmapped. Bound both
    // shm and dmabuf messages and let the worker drop frames instead of block.
    let (frame_tx, frame_rx) = sync_channel::<FrameMessage>(16);
    let capture_mgr = Rc::new(CaptureManager::new(frame_tx));
    let monitors = query_monitors();
    let clients = query_clients();
    let has_window_list_raw = window_list_raw.is_some();
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
        pick_hover_rx: None,
        capture_mgr: capture_mgr.clone(),
        highlighter,
        clients,
        monitors: monitors.clone(),
        window_entries,
        has_window_list_raw,
        next_card_id: 0,
        desktop_reg,
        selected_window_preview: None,
        selected_window_heading: None,
        selected_window_id: None,
        window_flow: None,
        window_group_lead: None,
        window_cards: HashMap::new(),
        last_active_ws: None,
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
        card_widgets: HashMap::new(),
        pictures,
        window: None,
        stack: None,
    }));

    // Hyprland state arrives pre-queried from a worker thread; the UI only
    // copies it into place.
    let hypr_rx = spawn_state_watcher();

    // Slurp pick completion and Hyprland state updates. This runs on a plain
    // timeout because it must keep working while the window is hidden for
    // slurp, when the frame clock is stopped.
    let state_loop = state.clone();
    glib::timeout_add_local(Duration::from_millis(100), move || {
        let mut latest_state = None;
        let mut windows_changed = false;
        while let Ok(snapshot) = hypr_rx.try_recv() {
            windows_changed |= snapshot.windows_changed;
            latest_state = Some(snapshot);
        }

        if let Some(snapshot) = latest_state {
            if let Ok(mut s) = state_loop.try_borrow_mut() {
                s.clients = snapshot.clients;
                if !snapshot.monitors.is_empty() {
                    s.monitors = snapshot.monitors;
                }
                s.last_active_ws = snapshot.active_workspace;
                if windows_changed {
                    // Let the capture worker re-enumerate toplevels so previews
                    // of newly opened windows can bind.
                    s.capture_mgr.refresh_targets();
                }
            }
        }
        // Rebuilding borrows the state mutably; skip a tick if it is busy.
        if windows_changed && state_loop.try_borrow_mut().is_ok() {
            refresh_window_cards(&state_loop);
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

    // A regular toplevel participates in Hyprland's move/resize bindings.
    // The existing app-ID rules make it floating, centered, and pinned.
    window.set_decorated(false);
    {
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
            let geom = mon.geometry();
            (geom.width(), geom.height())
        } else {
            (1920, 1080)
        };

        let win_w = 1180.min(mon_w - 60).max(640);
        let win_h = 800.min(mon_h - 60).max(460);
        window.set_default_size(win_w, win_h);
    }

    // Key handling: Esc to quit, Enter to share
    let key_controller = EventControllerKey::new();
    let state_key = state.clone();
    key_controller.connect_key_pressed(move |_ctrl, keyval, _keycode, _mod| {
        if keyval == gdk::Key::Escape || keyval == gdk::Key::q {
            if let Some(ref h) = state_key.borrow().highlighter {
                h.clear();
            }
            process::exit(1);
        }
        if keyval == gdk::Key::Return || keyval == gdk::Key::KP_Enter {
            let s = state_key.borrow();
            if let Some(ref sel) = s.selection {
                let final_sel = resolve_final_selection(sel, &s);
                emit_selection(&final_sel, s.allow_token, &s.window_entries);
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

    header.set_cursor_from_name(Some("grab"));
    header.set_tooltip_text(Some(
        "Drag to move · Super+drag anywhere · Double-click to center",
    ));

    let drag = GestureDrag::new();
    let win_drag = window.clone();
    drag.connect_drag_begin(move |gesture, x, y| {
        let Some(event) = gesture.current_event() else {
            return;
        };
        let Some(device) = event.device() else { return };
        let Some(surface) = win_drag.surface().and_downcast::<gdk::Toplevel>() else {
            return;
        };
        let (x, y) = event.position().unwrap_or((x, y));
        surface.begin_move(&device, 1, x, y, event.time());
    });
    header.add_controller(drag);

    let double_click = GestureClick::new();
    double_click.set_button(1);
    double_click.connect_pressed(move |_gesture, n_press, _x, _y| {
        if n_press == 2 {
            thread::spawn(|| {
                let dispatch = format!(
                    "hl.dsp.window.center({{ window = \"pid:{}\" }})",
                    process::id()
                );
                if !Command::new("hyprctl")
                    .args(["dispatch", &dispatch])
                    .output()
                    .is_ok_and(|output| output.status.success())
                {
                    eprintln!("hyprland-share-picker: could not center the picker");
                }
            });
        }
    });
    header.add_controller(double_click);

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

    let mut next_card_id = state.borrow().next_card_id;
    let desktop_reg = state.borrow().desktop_reg.clone();
    let window_page = make_window_page(state.clone(), &desktop_reg, &mut next_card_id);
    let screen_page = make_screen_page(state.clone(), &mut next_card_id);
    let region_page = make_region_page(state.clone(), &mut next_card_id);
    state.borrow_mut().next_card_id = next_card_id;

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
            let final_sel = resolve_final_selection(sel, &s);
            emit_selection(&final_sel, s.allow_token, &s.window_entries);
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
            {
                let mut s = state_tab_change.borrow_mut();
                s.active_tab = name.to_string();
                save_last_tab(&name);
                s.capture_mgr.set_active_tab(&name);
                update_pick_button_ui(&mut s);
                update_overlay_highlight(&s);
            }
            if let Ok(s) = state_tab_change.try_borrow() {
                update_card_fps(&s);
            }
        }
    });

    // Frame delivery rides the frame clock instead of a timer, so a texture is
    // swapped in right before the frame that will show it, and no work happens
    // while the window is hidden.
    let frame_state = state.clone();
    let release_sender = capture_mgr.command_sender();
    window.add_tick_callback(move |_widget, _clock| {
        let selected = {
            let s = frame_state.borrow();
            if let Some(highlighter) = s.highlighter.as_ref() {
                highlighter.refresh_picker_bounds();
            }
            s.selected_window_id.zip(s.selected_window_preview.clone())
        };
        deliver_frames(
            &frame_rx,
            &pictures_loop,
            &release_sender,
            selected.as_ref(),
        );
        glib::ControlFlow::Continue
    });

    // Cards that scrolled out of view stop capturing entirely.
    let state_visibility = state.clone();
    glib::timeout_add_local_once(Duration::from_millis(250), move || {
        if let Ok(s) = state_visibility.try_borrow() {
            update_card_fps(&s);
        }
    });

    capture_mgr.set_active_tab(&initial_tab);
    window.present();
}

/// Applies the newest frame per card. Older frames for the same card are
/// dropped without ever being uploaded, so a burst from the capture worker
/// costs one texture swap, not several.
fn deliver_frames(
    frame_rx: &Receiver<FrameMessage>,
    pictures: &Rc<RefCell<HashMap<usize, Picture>>>,
    release_sender: &Sender<CaptureCommand>,
    selected: Option<&(usize, Picture)>,
) {
    let mut latest: HashMap<usize, FramePayload> = HashMap::new();
    while let Ok(msg) = frame_rx.try_recv() {
        if let Some(superseded) = latest.insert(msg.card_id, msg.frame) {
            release_payload(superseded, release_sender);
        }
    }

    if latest.is_empty() {
        return;
    }

    let pics = pictures.borrow();
    for (card_id, payload) in latest {
        let Some(picture) = pics.get(&card_id) else {
            release_payload(payload, release_sender);
            continue;
        };

        if picture.paintable().is_none()
            && std::env::var_os("HYPRLAND_SHARE_PICKER_DEBUG").is_some()
        {
            let (width, height) = match &payload {
                FramePayload::Shm(frame) => (frame.width, frame.height),
                FramePayload::Dmabuf(frame) => (frame.width, frame.height),
            };
            eprintln!("hyprland-share-picker: first preview for card {card_id}: {width}x{height}");
        }

        match payload {
            FramePayload::Shm(frame) => {
                let texture = gdk::MemoryTexture::new(
                    frame.width,
                    frame.height,
                    gdk::MemoryFormat::R8g8b8a8,
                    &frame.bytes,
                    frame.stride,
                );
                picture.set_paintable(Some(&texture));
            }
            FramePayload::Dmabuf(frame) => {
                if let Some(texture) = import_dmabuf(frame, release_sender) {
                    picture.set_paintable(Some(&texture));
                }
            }
        }
        if let Some((selected_id, expanded)) = selected {
            if *selected_id == card_id {
                expanded.set_paintable(picture.paintable().as_ref());
            }
        }
    }
}

fn release_payload(payload: FramePayload, release_sender: &Sender<CaptureCommand>) {
    if let FramePayload::Dmabuf(frame) = payload {
        let _ = release_sender.send(CaptureCommand::ReleaseBuffer {
            buffer_id: frame.buffer_id,
        });
    }
}

/// Wraps a compositor-written dmabuf in a GDK texture. Nothing is copied: the
/// buffer stays on the GPU and the capture worker keeps it alive until the
/// release closure fires.
fn import_dmabuf(
    frame: DmabufFrame,
    release_sender: &Sender<CaptureCommand>,
) -> Option<gdk::Texture> {
    let display = gdk::Display::default()?;

    let builder = gdk::DmabufTextureBuilder::new();
    builder.set_display(&display);
    builder.set_width(frame.width.max(0) as u32);
    builder.set_height(frame.height.max(0) as u32);
    builder.set_fourcc(frame.fourcc);
    builder.set_modifier(frame.modifier);
    builder.set_n_planes(1);
    builder.set_fd(0, frame.fd.as_raw_fd());
    builder.set_stride(0, frame.stride);
    builder.set_offset(0, frame.offset);
    builder.set_premultiplied(true);

    let buffer_id = frame.buffer_id;
    let fd = frame.fd;
    let sender = release_sender.clone();

    // SAFETY: the fd stays open for as long as the texture lives, because it is
    // owned by the release closure GDK calls when it drops the texture.
    let result = unsafe {
        builder.build_with_release_func(move || {
            drop(fd);
            let _ = sender.send(CaptureCommand::ReleaseBuffer { buffer_id });
        })
    };

    match result {
        Ok(texture) => Some(texture),
        Err(err) => {
            eprintln!("hyprland-share-picker: importing a dmabuf preview failed: {err}");
            // The release closure never ran, so this buffer and its fd are
            // stranded. Give up on dmabuf rather than stranding more.
            let _ = release_sender.send(CaptureCommand::ReleaseBuffer { buffer_id });
            let _ = release_sender.send(CaptureCommand::DisableDmabuf);
            None
        }
    }
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

fn resolve_final_selection(selection: &str, state: &AppState) -> String {
    let Some(window_id) = selection.strip_prefix("window:") else {
        return selection.to_string();
    };

    // Window cards use XDPH's lower toplevel-handle ID directly. The direct
    // picker, however, identifies a client by its stable Hyprland ID. Convert
    // that ID back to the portal-authorized handle before emitting it.
    if state
        .window_entries
        .iter()
        .any(|entry| entry.id == window_id)
    {
        return selection.to_string();
    }

    let queried_clients = query_clients();
    let queried_monitors = query_monitors();
    let clients = if queried_clients.is_empty() {
        &state.clients
    } else {
        &queried_clients
    };
    let monitors = if queried_monitors.is_empty() {
        &state.monitors
    } else {
        &queried_monitors
    };

    let Some(client) = clients
        .iter()
        .find(|client| client.stable_id_string().as_deref() == Some(window_id))
    else {
        return selection.to_string();
    };

    if let Some(entry) = state.window_entries.iter().find(|entry| {
        entry.address.as_deref() == Some(client.address.as_str())
            || entry.id == client.stable_id_string().as_deref().unwrap_or_default()
    }) {
        return format!("window:{}", entry.id);
    }

    // A client opened after XDPH supplied its window list has no portal handle.
    // Capture its bounds as a region rather than returning an invalid window ID
    // to XDPH, which can crash its window-capture path.
    window_to_region(client, monitors).unwrap_or_else(|| selection.to_string())
}

/// Re-evaluates which cards are on screen whenever the list scrolls or is
/// resized, so off-screen previews stop capturing.
fn watch_scroll_for_culling(scroll: &ScrolledWindow, state: Rc<RefCell<AppState>>) {
    let adjustment = scroll.vadjustment();

    let state_scroll = state.clone();
    adjustment.connect_value_changed(move |_adj| {
        if let Ok(s) = state_scroll.try_borrow() {
            update_card_fps(&s);
        }
    });

    adjustment.connect_page_size_notify(move |_adj| {
        if let Ok(s) = state.try_borrow() {
            update_card_fps(&s);
        }
    });
}

fn make_window_page(
    state: Rc<RefCell<AppState>>,
    desktop_reg: &DesktopRegistry,
    next_id: &mut usize,
) -> GtkBox {
    let flow = FlowBox::new();
    flow.set_selection_mode(SelectionMode::None);
    let cols = state.borrow().config.columns;
    flow.set_max_children_per_line(cols as u32);
    flow.set_min_children_per_line(cols as u32);
    flow.set_homogeneous(true);
    flow.set_valign(gtk4::Align::Start);
    flow.set_column_spacing(14);
    flow.set_row_spacing(14);
    flow.set_margin_top(4);
    flow.set_margin_bottom(16);
    flow.set_margin_start(28);
    flow.set_margin_end(28);

    populate_window_cards(&state, &flow, desktop_reg, next_id);
    state.borrow_mut().window_flow = Some(flow.clone());

    let scroll = ScrolledWindow::new();
    scroll.set_policy(PolicyType::Never, PolicyType::Automatic);
    scroll.set_child(Some(&flow));
    watch_scroll_for_culling(&scroll, state.clone());
    scroll.set_hexpand(true);

    let expanded = GtkBox::new(Orientation::Vertical, 12);
    expanded.set_size_request(360, -1);
    expanded.set_margin_end(28);
    expanded.set_margin_bottom(16);
    expanded.set_visible(false);

    let heading = Label::new(None);
    heading.add_css_class("heading");
    heading.set_wrap(true);
    heading.set_max_width_chars(32);
    expanded.append(&heading);

    let preview = Picture::new();
    preview.add_css_class("region-preview");
    preview.set_can_shrink(true);
    preview.set_content_fit(ContentFit::Contain);
    preview.set_size_request(360, 240);
    preview.set_vexpand(true);
    expanded.append(&preview);

    {
        let mut s = state.borrow_mut();
        s.selected_window_preview = Some(preview);
        s.selected_window_heading = Some(heading);
    }

    let page = GtkBox::new(Orientation::Horizontal, 14);
    page.append(&scroll);
    page.append(&expanded);
    page
}

/// Fills `flow` with a card per window, sorted and filtered per the config.
fn populate_window_cards(
    state: &Rc<RefCell<AppState>>,
    flow: &FlowBox,
    desktop_reg: &DesktopRegistry,
    next_id: &mut usize,
) {
    let (entries, clients, monitors, only_visible, hide_special) = {
        let s = state.borrow();
        (
            s.window_entries.clone(),
            s.clients.clone(),
            s.monitors.clone(),
            s.config.only_visible,
            s.config.hide_special,
        )
    };

    let active_ws = query_active_workspace().map(|w| w.id);

    let mut sorted_entries: Vec<(PortalWindowEntry, Option<Client>)> =
        current_window_entries(&entries, &clients)
            .into_iter()
            .map(|e| {
                let cl = client_for_entry(&e, &clients).cloned();
                (e, cl)
            })
            .filter(|(_, cl)| {
                // Windows Hyprland does not know stay: they cannot be judged.
                cl.as_ref().is_none_or(|c| {
                    !(only_visible && !c.is_visible_on_any_monitor(&monitors)
                        || hide_special && c.workspace.id < 0)
                })
            })
            .collect();

    let is_visible = |c: &Option<Client>| {
        c.as_ref()
            .is_some_and(|c| c.is_visible_on_any_monitor(&monitors))
    };
    sorted_entries.sort_by(|(ea, ca), (eb, cb)| {
        let (visible_a, visible_b) = (is_visible(ca), is_visible(cb));
        if visible_a != visible_b {
            return visible_b.cmp(&visible_a);
        }
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

        let mut badges: Vec<(&str, &str, &str)> = Vec::new();
        if let Some(ref c) = client {
            if c.workspace.id < 0 {
                badges.push(("Special", "badge-special", "focus-windows-symbolic"));
            }
            if !c.is_visible_on_any_monitor(&monitors) {
                badges.push(("Off screen", "badge-offscreen", "view-conceal-symbolic"));
            }
        }

        let card = make_source_card(
            state.clone(),
            card_id,
            &selection,
            &title,
            &subtitle,
            Some(icon_widget),
            &badges,
            target,
            "windows",
            &mut group_lead,
        );
        flow.insert(&card, -1);
    }
}

/// The windows to list: XDPH's windows that are still open, then windows
/// opened since XDPH handed over its list. Those have no portal handle and
/// carry their stable Hyprland ID instead; sharing one goes through
/// `resolve_final_selection`.
fn current_window_entries(
    entries: &[PortalWindowEntry],
    clients: &[Client],
) -> Vec<PortalWindowEntry> {
    // Without a client list nothing can be judged.
    if clients.is_empty() {
        return entries.to_vec();
    }
    let mut current: Vec<PortalWindowEntry> = entries
        .iter()
        .filter(|e| {
            e.address
                .as_ref()
                .is_none_or(|a| clients.iter().any(|c| &c.address == a))
        })
        .cloned()
        .collect();
    let listed: Vec<&str> = current
        .iter()
        .filter_map(|e| client_for_entry(e, clients))
        .map(|c| c.address.as_str())
        .collect();
    current.extend(
        clients
            .iter()
            .filter(|c| c.mapped && !listed.contains(&c.address.as_str()))
            .filter_map(|c| {
                Some(PortalWindowEntry {
                    id: c.stable_id_string()?,
                    class: c.class.clone(),
                    title: c.title.clone(),
                    address: Some(c.address.clone()),
                })
            }),
    );
    current
}

/// Rebuilds the window cards after windows opened or closed, keeping the
/// selection when its window is still there.
fn refresh_window_cards(state: &Rc<RefCell<AppState>>) {
    let (flow, desktop_reg, removed, selection) = {
        let mut s = state.borrow_mut();
        let Some(flow) = s.window_flow.clone() else {
            return;
        };
        let removed: Vec<usize> = s
            .card_targets
            .iter()
            .filter(|(_, sel, _)| sel.starts_with("window:"))
            .map(|(id, _, _)| *id)
            .collect();
        s.card_targets
            .retain(|(_, sel, _)| !sel.starts_with("window:"));
        s.card_buttons
            .retain(|(sel, _)| !sel.starts_with("window:"));
        if s.hovered_id.is_some_and(|id| removed.contains(&id)) {
            s.hovered_id = None;
        }
        let selection = s.selection.clone().filter(|sel| sel.starts_with("window:"));
        (flow, s.desktop_reg.clone(), removed, selection)
    };
    for id in &removed {
        let card = {
            let s = state.borrow();
            s.capture_mgr.unregister_card(*id);
            s.pictures.borrow_mut().remove(id);
            s.card_widgets.get(id).cloned()
        };
        if let Some(card) = card {
            flow.remove(&card);
        }
        state.borrow_mut().card_widgets.remove(id);
    }

    let mut next_id = state.borrow().next_card_id;
    populate_window_cards(state, &flow, &desktop_reg, &mut next_id);
    state.borrow_mut().next_card_id = next_id;

    if let Some(selection) = selection {
        let card = state
            .borrow()
            .card_buttons
            .iter()
            .find(|(sel, _)| *sel == selection)
            .map(|(_, card)| card.clone());
        match card {
            Some(card) => card.set_active(true),
            None => {
                // The selected window closed.
                let mut s = state.borrow_mut();
                s.selection = None;
                s.selected_window_id = None;
                if let Some(ref btn) = s.share_button {
                    btn.set_sensitive(false);
                }
                if let Some(panel) = s.selected_window_preview.as_ref().and_then(|p| p.parent()) {
                    panel.set_visible(false);
                }
            }
        }
    }

    let s = state.borrow();
    update_card_fps(&s);
    update_overlay_highlight(&s);
}

fn make_screen_page(state: Rc<RefCell<AppState>>, next_id: &mut usize) -> ScrolledWindow {
    let flow = FlowBox::new();
    flow.set_selection_mode(SelectionMode::None);
    let cols = state.borrow().config.columns;
    flow.set_max_children_per_line(cols as u32);
    flow.set_min_children_per_line(cols as u32);
    flow.set_homogeneous(true);
    flow.set_valign(gtk4::Align::Start);
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
            &[],
            target,
            "screens",
            &mut group_lead,
        );
        flow.insert(&card, -1);
    }

    let scroll = ScrolledWindow::new();
    scroll.set_policy(PolicyType::Never, PolicyType::Automatic);
    scroll.set_child(Some(&flow));
    watch_scroll_for_culling(&scroll, state.clone());
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
    badges: &[(&str, &str, &str)],
    target: CaptureTarget,
    tab: &str,
    group_lead: &mut Option<ToggleButton>,
) -> ToggleButton {
    let card = ToggleButton::new();
    card.add_css_class("source-card");
    card.set_hexpand(true);
    card.set_vexpand(false);
    card.set_valign(gtk4::Align::Start);
    card.set_size_request(240, 246);

    if let Some(lead) = group_lead {
        card.set_group(Some(lead));
    } else {
        *group_lead = Some(card.clone());
    }

    let body = GtkBox::new(Orientation::Vertical, 0);
    body.set_vexpand(false);
    body.set_hexpand(true);

    let preview = Picture::new();
    preview.set_can_shrink(true);
    preview.set_content_fit(ContentFit::Contain);
    preview.set_halign(gtk4::Align::Fill);
    preview.set_valign(gtk4::Align::Fill);
    preview.set_hexpand(true);
    preview.set_vexpand(true);

    let preview_box = ScrolledWindow::new();
    preview_box.add_css_class("preview");
    preview_box.set_policy(PolicyType::Never, PolicyType::Never);
    preview_box.set_size_request(-1, 170);
    preview_box.set_hexpand(true);
    preview_box.set_vexpand(false);
    preview_box.set_child(Some(&preview));

    // Badges such as "Special" sit on the preview's top right corner.
    let preview_overlay = gtk4::Overlay::new();
    preview_overlay.set_child(Some(&preview_box));
    if !badges.is_empty() {
        let badge_row = GtkBox::new(Orientation::Horizontal, 6);
        badge_row.set_halign(gtk4::Align::End);
        badge_row.set_valign(gtk4::Align::Start);
        badge_row.set_margin_top(8);
        badge_row.set_margin_end(8);
        badge_row.set_can_target(false);
        for (text, class, icon) in badges {
            let badge = GtkBox::new(Orientation::Horizontal, 4);
            badge.add_css_class("card-badge");
            badge.add_css_class(class);
            let image = Image::from_icon_name(icon);
            image.set_pixel_size(12);
            badge.append(&image);
            badge.append(&Label::new(Some(text)));
            badge_row.append(&badge);
        }
        preview_overlay.add_overlay(&badge_row);
    }
    body.append(&preview_overlay);

    let info_box = GtkBox::new(Orientation::Horizontal, 12);
    info_box.add_css_class("card-info");
    info_box.set_size_request(-1, 56);
    info_box.set_margin_top(8);
    info_box.set_margin_bottom(12);
    info_box.set_margin_start(14);
    info_box.set_margin_end(14);
    info_box.set_valign(gtk4::Align::Center);
    info_box.set_vexpand(false);
    info_box.set_hexpand(true);

    if let Some(ref icon_w) = icon {
        info_box.append(icon_w);
    }

    let labels = GtkBox::new(Orientation::Vertical, 2);
    labels.set_hexpand(true);
    labels.set_valign(gtk4::Align::Center);

    let clean_title = title.replace(['\r', '\n'], " ");
    let name_label = Label::new(Some(&clean_title));
    name_label.set_xalign(0.0);
    name_label.set_single_line_mode(true);
    name_label.set_lines(1);
    name_label.set_ellipsize(gtk4::pango::EllipsizeMode::End);
    name_label.add_css_class("heading");

    let clean_subtitle = subtitle.replace(['\r', '\n'], " ");
    let detail_label = Label::new(Some(&clean_subtitle));
    detail_label.set_xalign(0.0);
    detail_label.set_single_line_mode(true);
    detail_label.set_lines(1);
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
        s.card_widgets.insert(card_id, card.clone());
    }

    // A tab switch can park cards before GTK maps the new page. Resume each
    // card when it is actually mapped, even if the scroll allocation is unchanged.
    let state_mapped = state.clone();
    card.connect_map(move |_| {
        if let Ok(s) = state_mapped.try_borrow() {
            update_card_fps(&s);
        }
    });

    // Toggle event
    let state_toggle = state.clone();
    let sel_toggle = sel_str.clone();
    let name_label_for_preview = clean_title.clone();
    card.connect_toggled(move |c| {
        if c.is_active() {
            {
                let mut s = match state_toggle.try_borrow_mut() {
                    Ok(s) => s,
                    Err(_) => return,
                };
                s.selection = Some(sel_toggle.clone());
                if sel_toggle.starts_with("window:") {
                    s.selected_window_id = Some(card_id);
                    if let Some(expanded) = s.selected_window_preview.as_ref() {
                        if let Some(picture) = s.pictures.borrow().get(&card_id) {
                            expanded.set_paintable(picture.paintable().as_ref());
                        }
                        if let Some(panel) = expanded.parent() {
                            panel.set_visible(true);
                        }
                    }
                    if let Some(heading) = s.selected_window_heading.as_ref() {
                        heading.set_label(&name_label_for_preview);
                    }
                }
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
            let s = state_click.borrow();
            let final_sel = resolve_final_selection(&sel_click, &s);
            emit_selection(&final_sel, allow_token, &s.window_entries);
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
        }
        // Moving to the next card crosses a gap with nothing hovered. Wait
        // before falling back, so the dim does not drop out in between.
        let state_later = state_leave.clone();
        glib::timeout_add_local_once(HOVER_LEAVE_DELAY, move || {
            if let Ok(s) = state_later.try_borrow() {
                if s.hovered_id.is_none() {
                    update_overlay_highlight(&s);
                }
            }
        });
    });

    card.add_controller(motion);
    card
}

/// Whether a card overlaps the visible part of its scroller. Cards that have
/// not been laid out yet count as visible so they are not parked before their
/// first frame.
fn card_is_in_viewport(card: &ToggleButton) -> bool {
    if !card.is_mapped() {
        return false;
    }

    let Some(viewport) = card.ancestor(ScrolledWindow::static_type()) else {
        return true;
    };
    let Some(bounds) = card.compute_bounds(&viewport) else {
        return true;
    };

    let height = viewport.height() as f32;
    if height <= 0.0 {
        return true;
    }

    bounds.y() < height && bounds.y() + bounds.height() > 0.0
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
        let visible = match state.card_widgets.get(id) {
            // The region preview has no card widget; it is always live.
            None => true,
            Some(card) => card_is_in_viewport(card),
        };

        let fps = if Some(*id) == focused_id
            || Some(*id) == state.selected_window_id
            || (state.active_tab == "regions" && state.card_widgets.get(id).is_none())
        {
            high_fps
        } else if visible {
            1.0
        } else {
            // Parked: scrolled out of view, so nothing would be shown anyway.
            0.0
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

    // Cached state only: this runs on every hover change, and the Hyprland IPC
    // queries block on a unix socket. The state watcher keeps both lists fresh.
    let monitors_to_use = state.monitors.clone();

    if let Some(name) = sel.strip_prefix("screen:") {
        highlighter.highlight_screen(name);
    } else if let Some(id) = sel.strip_prefix("window:") {
        // Window cards carry XDPH's handle ID, the direct picker a stable
        // Hyprland ID.
        let client = match state.window_entries.iter().find(|e| e.id == id) {
            Some(entry) => client_for_entry(entry, &state.clients),
            None => state
                .clients
                .iter()
                .find(|cl| cl.stable_id_string().as_deref() == Some(id)),
        };
        if let Some(c) = client {
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
    // Nothing is on screen to preview while slurp owns the display, and the
    // compositor should not be doing capture work during the drag.
    state.borrow().capture_mgr.set_paused(true);

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
    // Nothing is on screen to preview while slurp owns the display, and the
    // compositor should not be doing capture work during the drag.
    state.borrow().capture_mgr.set_paused(true);

    let (hover_tx, hover_rx) = channel::<Option<Client>>();
    state.borrow_mut().pick_hover_rx = Some(hover_rx);
    let state_hover = state.clone();
    glib::timeout_add_local(Duration::from_millis(30), move || {
        let Ok(mut s) = state_hover.try_borrow_mut() else {
            return glib::ControlFlow::Continue;
        };
        let Some(rx) = s.pick_hover_rx.as_ref() else {
            return glib::ControlFlow::Break;
        };
        let mut latest = None;
        let mut finished = false;
        loop {
            match rx.try_recv() {
                Ok(client) => latest = Some(client),
                Err(std::sync::mpsc::TryRecvError::Empty) => break,
                Err(std::sync::mpsc::TryRecvError::Disconnected) => {
                    finished = true;
                    break;
                }
            }
        }
        if let (Some(client), Some(h)) = (latest, s.highlighter.as_ref()) {
            h.highlight_window_standalone(client.as_ref(), &s.monitors);
        }
        if finished {
            s.pick_hover_rx = None;
            return glib::ControlFlow::Break;
        }
        glib::ControlFlow::Continue
    });

    let (tx, rx) = channel::<Option<String>>();
    thread::spawn(move || {
        // Windows on hidden workspaces keep their geometry; skip them.
        let monitors = query_monitors();
        let clients: Vec<_> = query_clients()
            .into_iter()
            .filter(|c| monitors.is_empty() || c.is_visible_on_any_monitor(&monitors))
            .collect();

        // slurp only takes the click and draws nothing. The window under
        // the cursor is marked the same way as a hovered card, and the
        // click resolves with the same lookup.
        let done = Arc::new(AtomicBool::new(false));
        let follower = {
            let done = done.clone();
            let clients = clients.clone();
            thread::spawn(move || {
                let mut last: Option<String> = None;
                while !done.load(Ordering::Relaxed) {
                    let hovered =
                        query_cursor_pos().and_then(|pos| window_at_point(pos.x, pos.y, &clients));
                    let address = hovered.map(|c| c.address.clone());
                    if address != last {
                        let _ = hover_tx.send(hovered.cloned());
                        last = address;
                    }
                    thread::sleep(Duration::from_millis(30));
                }
            })
        };

        let transparent = "#00000000";
        let res = Command::new("slurp")
            .args(["-p", "-f", "%x %y"])
            .args(["-b", transparent, "-c", transparent, "-s", transparent])
            .output();
        done.store(true, Ordering::Relaxed);
        let _ = follower.join();
        decoration::restore();

        let selection = res.ok().filter(|out| out.status.success()).and_then(|out| {
            let text = String::from_utf8_lossy(&out.stdout).into_owned();
            let mut parts = text.split_whitespace().map(str::parse::<i32>);
            match (parts.next(), parts.next()) {
                (Some(Ok(x)), Some(Ok(y))) => window_at_point(x, y, &clients)
                    .and_then(|c| c.stable_id_string())
                    .map(|id| format!("window:{id}")),
                _ => None,
            }
        });

        let _ = tx.send(selection);
    });

    state.borrow_mut().pick_receiver = Some(rx);
}

fn trigger_pick_region(state: Rc<RefCell<AppState>>) {
    let (tx, rx) = channel::<Option<String>>();
    let (window, monitors) = {
        let mut s = state.borrow_mut();
        if s.pick_receiver.is_some() {
            return;
        }
        s.pick_receiver = Some(rx);
        s.capture_mgr.set_paused(true);
        if let Some(ref h) = s.highlighter {
            h.clear();
        }
        (s.window.clone(), s.monitors.clone())
    };
    // Mapping emits GTK signals synchronously; do not hold AppState across it.
    if let Some(window) = window {
        window.set_visible(false);
    }
    eprintln!("hyprland-share-picker: starting region chooser");
    thread::spawn(move || {
        let res = Command::new("slurp")
            .args(["-f", "%o %x %y %w %h"])
            .output();

        let selection = if let Ok(out) = res {
            eprintln!(
                "hyprland-share-picker: region chooser exited: {}",
                out.status
            );
            if out.status.success() {
                let s = String::from_utf8_lossy(&out.stdout);
                parse_region(&s, &monitors)
            } else {
                None
            }
        } else {
            eprintln!("hyprland-share-picker: could not start region chooser");
            None
        };

        let _ = tx.send(selection);
    });
}

fn finish_pick(state: Rc<RefCell<AppState>>, selection: Option<String>) {
    // Stale hover updates must not dim outputs after the pick.
    state.borrow_mut().pick_hover_rx = None;
    if let Some(ref h) = state.borrow().highlighter {
        h.clear();
    }
    // A picked screen or window is final: hand it to XDPH right away. The
    // direct window picker yields a stable Hyprland ID, which must become
    // the portal handle first or XDPH's window capture crashes.
    if let Some(sel) = selection.as_deref().filter(|s| !s.starts_with("region:")) {
        let s = state.borrow();
        let final_sel = resolve_final_selection(sel, &s);
        emit_selection(&final_sel, s.allow_token, &s.window_entries);
    }

    let window = state.borrow().window.clone();
    if let Some(win) = window {
        // Reusing the hidden native surface can leave GTK's widget mapped
        // while its Wayland surface stays unmapped after slurp exits. Drop
        // that surface so present() creates a new toplevel and frame clock.
        WidgetExt::unrealize(&win);
        win.present();
    }
    eprintln!("hyprland-share-picker: restored picker after chooser");
    state.borrow().capture_mgr.set_paused(false);

    if let Some(sel) = selection {
        set_region_selection(state.clone(), &sel);
    }
    update_overlay_highlight(&state.borrow());
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

pub fn emit_selection(selection: &str, allow_token: bool, window_entries: &[PortalWindowEntry]) {
    decoration::restore();
    if let Some(target) = indicator::target_for_selection(selection, window_entries) {
        indicator::spawn(&target);
    }
    let prefix = if allow_token { "r" } else { "" };
    let record = format!("[SELECTION]{prefix}/{selection}\n");
    let mut out = stdout().lock();
    let _ = out.write_all(record.as_bytes());
    let _ = out.flush();
    process::exit(0);
}
